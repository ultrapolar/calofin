;;; ======================================================================
;;; OASIS.lsp  --  continuous-tangent pool inside a given X/Y envelope
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  OASIS       draw a continuous-tangent pool
;;;            OASISVER    print the loaded version
;;; ======================================================================
;;;
;;; The shape
;;; ---------
;;; An oasis pool is arcs and nothing else: no corners, and at most one
;;; straight run.  It is a ring of BULGES -- circles pinned to the
;;; envelope -- with a JOINER between each consecutive pair, and a joiner
;;; is either a smaller reverse arc curving back IN, or, when both bulges
;;; are tangent to the same bound, the straight run of that bound between
;;; them.  Every joint is smooth: the outline changes direction without
;;; ever changing tangent, which is why the whole thing can be given as a
;;; handful of radii and two overall dimensions.
;;;
;;; Four families come out of that, and the first question is which:
;;;
;;;   Center    three bulges -- left, right and one across the top,
;;;             centred -- joined by three reverse arcs.
;;;   TopRight  the same, with the third bulge tucked into the top-right
;;;             corner instead.
;;;   Cloud     two bulges, joined over the top by a reverse arc.
;;;   Kidney    three bulges and ONE reverse arc: the two side circles
;;;             sit INSIDE the big top circle, touching it from within,
;;;             and the outline hands straight over at each touch --
;;;             a SEAM, the one joint with nothing drawn between.
;;;
;;; The two families that come two ways get a second question of their
;;; own, asked straight after.  A cloud is one shape with two bottoms:
;;; Straight, the flat run of the Y-min bound between the two bulges, or
;;; Rounded, a reverse arc like any other joiner.  A kidney is one shape
;;; whose sides are either matched or not: on a TRUE kidney the top
;;; radius is given and the two equal sides are DERIVED from having to
;;; touch it; on an ASYMMETRIC one the two unequal sides are given and
;;; the top circle is derived -- tangent to the top bound and both
;;; sides, its centre landing wherever those three contacts put it.
;;; The pair of answers together names one of six rings.
;;;
;;;                        top bulge
;;;                      ___________                  ___________
;;;          top-left  ,'           `.  top-right   ,'           `.
;;;          tangent  /               \  tangent    /               \
;;;                  |                 |          |                 |
;;;      left bulge  |                 |  right   |         .        |
;;;                   \      ___      /                     \___,'
;;;                    `.__,'   `.__,'             `._____________,'
;;;                     bottom-center                straight bottom
;;;
;;; Nothing downstream of the solver knows which shape it is looking at.
;;; It reads the ring.
;;;
;;; Where the circles sit
;;; ---------------------
;;; The X and Y the user gives are ABSOLUTE bounds -- the pool touches
;;; all four of them and crosses none.  That pins the three bulges with
;;; no further input:
;;;
;;;   left bulge    the two OASIS shapes: the X-min and Y-min bounds
;;;                                                     -> centre (rL, rL)
;;;                 the two CLOUD shapes: the X-min, Y-min AND Y-max
;;;                 bounds all at once, which pins the radius itself at
;;;                 half the Y bound and takes it out of the questions
;;;                                                     -> centre (Y/2, Y/2)
;;;   right bulge   touches the X-max and Y-min bounds  -> centre (X-rR, rR)
;;;   top bulge     CENTER    touches the Y-max bound, centred across X
;;;                                                     -> centre (X/2, Y-rT)
;;;                 TOPRIGHT  touches the Y-max AND the X-max bound
;;;                                                     -> centre (X-rT, Y-rT)
;;;                 the cloud shapes have no third bulge.
;;;
;;; So on an oasis the box's bottom edge is held by the two side bulges
;;; (each dips to it), the left edge by the left bulge, the top edge by
;;; the top bulge -- and the right edge by the right bulge alone on a
;;; centre-bulge pool, or by the right bulge AND the corner bulge, with
;;; a reverse curve between them, on a top-right one.  On a cloud the
;;; left bulge alone holds three of the four bounds, and the right bulge
;;; the fourth.  On a centre-bulge
;;; pool the top bulge has one degree of freedom left and it is spent
;;; centring it: oasis:*topfrac* moves it along X if a job ever needs it
;;; off-centre.  The corner bulge has none -- two tangencies pin it.
;;;
;;; Each tangent radius is then the circle of that radius sitting
;;; externally tangent to both of its neighbouring bulges -- two such
;;; circles exist, one either side of the line joining the two bulge
;;; centres, and the one OUTSIDE the pool is the one wanted.  Listing
;;; the bulges counter-clockwise (left, right, top) makes that choice
;;; mechanical: a counter-clockwise ring keeps its inside on the left,
;;; so outside is always the right-hand solution.  The pool then reads
;;; counter-clockwise as
;;;
;;;   left -> bottom-center -> right -> top-right -> top -> top-left ->
;;;
;;; and every arc's two ends are the tangent points it shares with its
;;; neighbours: a bulge runs from the neighbour before it to the one
;;; after, a reverse tangent arc runs the other way round its own
;;; circle.  Nothing is trimmed and nothing is fitted -- the six arcs
;;; are computed closed and drawn closed.
;;;
;;; What it draws
;;; -------------
;;; Where it goes is picked first, and then the pool is drawn AS IT IS
;;; ANSWERED.  Before every question the preview is redrawn, with three
;;; things overlapping on purpose: the outline solid on the POOL layer,
;;; the circle each arc is cut from dashed on POOL-GUIDE behind it, and a
;;; label on every circle -- its radius once given, "?" until then.  The
;;; circle the question is about goes red, arc, circle and label
;;; together, so there is never a doubt which radius is wanted.  A radius
;;; not yet answered still needs a value for any of that to be drawable,
;;; so the preview fills the gaps with the proportions an oasis usually
;;; comes in -- a side bulge three quarters of the way across the short
;;; bound, the top bulge half way across the long one -- and marks every
;;; one it invented with its "?".  On a 40 x 20 that starts the run at
;;; 7'-6" side bulges and a 10'-0" top, against the 8'/9' and 11' of the
;;; drawing this tool was written from: near enough that the first
;;; question is already looking at a familiar shape.
;;;
;;; When the last answer is in, the preview is erased and the real thing
;;; goes down:
;;;
;;;   * the six arcs on the POOL layer;
;;;   * the overall X and Y and a radius on each of the six arcs -- eight
;;;     dimensions, on the DIMENSION layer, in the drawing's ordinary
;;;     dimension style.  This is not asked about; a pool is always
;;;     dimensioned;
;;;   * a CHECK DRAWING clear to the right, dimensioned the way a layout
;;;     is checked rather than the way it is built: every circle centre
;;;     tied back to the two envelope corners nearest it, and every pair
;;;     of neighbouring centres tied to each other, and every pair of
;;;     neighbouring BULGES tied across whatever sits between them.
;;;     Between them those pin every centre against the box and against
;;;     one another, so a transcription slip in any single radius shows
;;;     up as a dimension that does not agree with the order sheet.  The
;;;     ring ties have a second use: neighbouring circles are externally
;;;     tangent by construction, so each of those must read exactly the
;;;     two radii added together.  The bulge ties are the lobe-to-lobe
;;;     measurements a pool is actually read by, and the ring ties never
;;;     cross a reverse arc to give them.
;;;
;;; The check drawing's eighteen are drawn in the CROSS DIMENSIONS
;;; style, since that is what they are; the pool's own eight are left in
;;; the drawing's ordinary style, because the pool is a plan and reads
;;; like one.  A drawing that has not got one of those styles is told so
;;; once and those dims come out in whatever style is current -- an
;;; invented style would look right and measure wrong.  The envelope box
;;; is construction: dashed on the check drawing where the corners are
;;; being measured to, and not drawn at all on the pool itself.
;;;
;;; Which frame it is drawn in
;;; -------------------------
;;; The pool is laid out in the CURRENT UCS, so it follows the way the
;;; user is working and the dimensions read the X and Y that were typed.
;;; An ARC entity is the one thing that cannot follow: its centre is
;;; stored in WORLD coordinates and its angles are measured from the
;;; world X axis, so oasis:draw carries both across.  A UCS tilted out of
;;; the world plan is refused outright -- the arcs would each need an
;;; extrusion of their own, and a plan pool has no business in one.
;;;
;;; What it refuses
;;; ---------------
;;; Three things make the shape impossible rather than merely ugly, and
;;; each is caught at the question that causes it rather than after all
;;; eight answers are in:
;;;
;;;   * a bulge that does not fit the envelope.  A side bulge is tangent
;;;     to the bottom edge AND to its own side, so it is twice its
;;;     radius both ways: more than half the Y bound and it pushes out
;;;     through the top, more than half the X bound and it pushes out
;;;     through the far side.  The TOP RIGHT corner bulge is checked the
;;;     same way, for the same reason; the CENTER one is not, because it
;;;     is trimmed away long before it reaches anything;
;;;   * one bulge circle wholly inside another: no tangent radius of any
;;;     size can bridge them, because raising it grows both reaches
;;;     equally;
;;;   * a tangent radius too small to span the gap between its two
;;;     bulges -- the routine says the smallest one that will.
;;;
;;; Anything that is merely unusual is drawn and reported, not refused.
;;; Two things are measured on the finished outline and named if they are
;;; wrong: whether it stays inside the envelope, and whether it runs
;;; through itself -- radii wildly out of proportion can send one arc
;;; clean through another even though all six exist and close.  Both
;;; reports name the ARC at fault rather than guess at the radius behind
;;; it, and both are drawn anyway, so the problem is on the screen where
;;; it can be seen and one U takes it away.
;;; ======================================================================
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.

(setq *oasis-version* "v5.0")   ; announced on load; release_lisp.py
                                ; reads this banner and stamps the
                                ; dated twin in releases/ from it

;;; -------------------- tunables ----------------------------------------

(setq oasis:*poollayer*  "POOL")       ; the six arcs
(setq oasis:*poolcolor*  4)
(setq oasis:*dimlayer*   "DIMENSION")  ; every dimension
(setq oasis:*dimcolor*   2)
(setq oasis:*guidelayer* "POOL-GUIDE") ; the dashed circles, box and labels
(setq oasis:*guidecolor* 8)
(setq oasis:*hicolor*    1)            ; red: the part being asked about

;; Where a Center pool's top bulge sits across the X bound, as a fraction
;; of it.  0.5 centres it, which is what every one on file wants; the
;; value is here so an off-centre one does not need the file edited.
(setq oasis:*topfrac* 0.5)

;; Slack for "is this the same point / the same length" tests, drawing
;; units.  Measurements arrive in inches, so this is far below anything
;; a tape can tell apart.
(setq oasis:*fuzz* 1.0e-6)

;; Two styles, because the two drawings are read differently: the pool
;; itself is a plan and is dimensioned in the drawing's ordinary style,
;; while the check drawing beside it is nothing but tie measurements and
;; goes in the cross-dimension style, same as every other cross dim in
;; the repo.  A drawing that has not got one of them is told so once and
;; those dims come out in whatever style is current -- an invented style
;; would look right and measure wrong.
(setq oasis:*dimstyle*   "Standard")           ; the pool's own dims
(setq oasis:*crossstyle* "CROSS DIMENSIONS")   ; the check drawing's

;; The check drawing sits this far to the right of the pool, measured
;; from the pool's own right-hand bound, as a multiple of the dimension
;; stand-off.  Big enough to clear the radius dims on that side.
(setq oasis:*checkgap* 4.0)

;; The shape the preview starts from, before any radius has been given:
;; how far across the envelope a side bulge and the top bulge usually
;; reach, as fractions.  Three quarters of the short bound and half the
;; long one is what an oasis normally comes in, so the first question is
;; already looking at something familiar.
(setq oasis:*startside* 0.75)
(setq oasis:*starttop*  0.5)

;;; -------------------- the four shapes ----------------------------------
;;; Every one of them is a ring of BULGES -- circles pinned to the
;;; envelope -- with a JOINER between each consecutive pair.  A joiner is
;;; either a reverse arc of a radius the user gives, or, when both bulges
;;; are tangent to the same bound, the straight run of that bound between
;;; them.  Nothing downstream of the solver knows which shape it is
;;; looking at: it reads the ring.
;;;
;;; Three bulges -- left, right, top -- and three reverse arcs:
;;;
;;;   Center     the top bulge sits across the top, centred.
;;;   TopRight   it is tucked into the top-right corner instead, tangent
;;;              to the Y-max AND the X-max bound.
;;;
;;; Two bulges -- left and right -- with the top joined by a reverse arc
;;; and the bottom either way.  The left bulge is tangent to the X-min,
;;; Y-min AND Y-max bounds all at once, which pins it at half the Y bound
;;; and takes it out of the questions altogether:
;;;
;;;   StraightBottom  the bottom is the flat run of the Y-min bound
;;;                   between the two bulges.
;;;   RoundedBottom   the bottom is a reverse arc like any other joiner.

;; T for the two-bulge shapes.
(defun oasis:cloud-p (variant)
  (member variant '("StraightBottom" "RoundedBottom")))

;; T for the kidney shapes.
(defun oasis:kidney-p (variant)
  (member variant '("TrueKidney" "AsymKidney")))

;; The shape, resolved.  The first question offers four families --
;; Center, TopRight, Cloud and Kidney -- and the two families that come
;; two ways get a second question of their own, asked straight after: a
;; cloud is one shape with two bottoms, a kidney one shape whose sides
;; are either matched or not.  The pair of answers together names one of
;; the six rings.
(defun oasis:variant (ans)
  (cond ((= (nth 0 ans) "Cloud")
         (if (= (nth 10 ans) "Rounded") "RoundedBottom" "StraightBottom"))
        ((= (nth 0 ans) "Kidney")
         (if (= (nth 10 ans) "Asymmetric") "AsymKidney" "TrueKidney"))
        ((nth 0 ans))))

;; The left bulge's radius.  On a cloud shape three bounds pin it at once
;; -- left, bottom and top -- so it is half the Y bound and is never
;; asked for; on an oasis it is whatever was typed.
(defun oasis:leftrad (variant h rl)
  (if (oasis:cloud-p variant) (if h (* 0.5 h)) rl))

;; Where the third bulge sits, on the shapes that have one.
(defun oasis:topcen (w h rt variant)
  (if (= variant "TopRight")
      (list (- w rt) (- h rt))
      (list (* w oasis:*topfrac*) (- h rt))))

;; What the ring's elements are called, in the order they run round the
;; pool: bulges at the even positions, joiners at the odd ones.  A seam
;; -- the direct handover where a kidney's side circle touches the top
;; circle from inside -- is a joiner with nothing to draw, so its name
;; never reaches the drawing.
(defun oasis:names (variant)
  (cond ((oasis:cloud-p variant)
         '("left" "bottom" "right" "top"))
        ((oasis:kidney-p variant)
         '("left" "bottom-center" "right" "right-seam" "top-center"
           "left-seam"))
        ((= variant "TopRight")
         '("left" "bottom-center" "right" "right-side" "top-right"
           "top-left"))
        (t
         '("left" "bottom-center" "right" "top-right" "top" "top-left"))))

;; What the question for one answer slot is called.  The wording follows
;; the shape, because "top-right" is the joiner on one and the bulge
;; itself on another.
(defun oasis:sprompt (variant slot)
  (cond
    ((oasis:cloud-p variant)
      (cond ((= slot 6) "Right bulge radius")
            ((= slot 7) "Top tangent radius")
            ((= slot 9) "Bottom radius")))
    ((oasis:kidney-p variant)
      (cond ((= slot 4) "Left bulge radius")
            ((= slot 5) "Top-center radius")
            ((= slot 6) "Right bulge radius")
            ((= slot 9) "Bottom-center tangent radius")))
    (t
      (cond ((= slot 4) "Left bulge radius")
            ((= slot 5) (if (= variant "TopRight")
                            "Top-right bulge radius" "Top bulge radius"))
            ((= slot 6) "Right bulge radius")
            ((= slot 7) "Top-left tangent radius")
            ((= slot 8) (if (= variant "TopRight")
                            "Right-side tangent radius"
                            "Top-right tangent radius"))
            ((= slot 9) "Bottom-center tangent radius")))))

;; Which answer slots this shape asks for, in the order it asks them.
;; The rest are either pinned by the envelope (a cloud's left bulge) or
;; are no part of the shape at all.
(defun oasis:steps (ans / fam)
  (setq fam (nth 0 ans))
  (cond ((= fam "Cloud")
         (if (= (nth 10 ans) "Rounded") '(0 10 1 2 3 6 7 9)
             '(0 10 1 2 3 6 7)))
        ((= fam "Kidney")
         (if (= (nth 10 ans) "Asymmetric") '(0 10 1 2 3 4 6 9)
             '(0 10 1 2 3 5 9)))
        (t '(0 1 2 3 4 5 6 7 8 9))))

;; How the shape is named on the command line and in the report.
(defun oasis:vlabel (variant)
  (cond ((= variant "TopRight")       "top-right-bulge")
        ((= variant "StraightBottom") "straight-bottom cloud")
        ((= variant "RoundedBottom")  "rounded-bottom cloud")
        ((= variant "TrueKidney")     "true kidney")
        ((= variant "AsymKidney")     "asymmetric kidney")
        (t                            "center-bulge")))

;; T when the shape's third bulge has to fit the envelope the way a side
;; bulge does.  The corner one is tangent to two bounds, so it is twice
;; its radius both ways and can break out of either; the centred one is
;; trimmed away long before it reaches anything.
(defun oasis:topfits-p (variant) (= variant "TopRight"))

;;; -------------------- snaps and the dimension style --------------------

;; Make the cross-dimension style current for the dims about to be drawn.
;; A missing style is NOT invented: the dims come out in whatever style is
;; current and the routine says so once, so a drawing started from the
;; wrong template is obvious instead of quietly producing wrong-looking
;; dims.  (The CDCREATE rule, CDCREATE.lsp:80.)
(defun oasis:dimstyle-on (name)
  (cond ((tblsearch "DIMSTYLE" name)
         (command "_.-DIMSTYLE" "_Restore" name)
         T)
        (t
         (princ (strcat "\nOASIS: this drawing has no \"" name
                        "\" dimension style -- those dims drawn in \""
                        (getvar "DIMSTYLE")
                        "\" instead.  Create the style (or start from the"
                        " standard template) and re-run."))
         nil)))

;;; -------------------- linetypes ----------------------------------------

;; Build a linetype from an explicit pattern (positive = dash length,
;; negative = gap), in drawing units.  Done with entmake rather than
;; loading acad.lin: a failed load falls back to CONTINUOUS silently,
;; which is how dashes vanish.  (From pool:ltmake, POOL.LSP:251.)
(defun oasis:ltmake (name descr pat / lst x)
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
;; pattern defined in drawing units always plots at that size however the
;; host drawing is set up.  (From pool:ltsc, POOL.LSP:271.)
(defun oasis:ltsc ( / s)
  (setq s (getvar "LTSCALE"))
  (if (or (null s) (<= s 0.0)) 1.0 (/ 1.0 s)))

;; The dash pattern the guide circles are drawn with, scaled to the pool
;; so it reads the same on a 10-foot spa and a 40-foot pool.
(defun oasis:dashlt (w h / d)
  (setq d (max 2.0 (/ (max w h) 40.0)))
  (oasis:ltmake "OASISDASH" "Oasis guide __ __ __ __" (list d (- 0.0 d))))

;;; -------------------- geometry ----------------------------------------

;; Intersection of circle (c1 r1) with circle (c2 r2).  side 1.0 is the
;; point left of the c1->c2 direction, -1.0 the one right of it.  nil
;; when the two circles never meet.
(defun oasis:circint (c1 r1 c2 r2 side / d ux uy a h2 h bx by)
  (setq d (distance c1 c2))
  (if (> d oasis:*fuzz*)
      (progn
        (setq ux (/ (- (car c2) (car c1)) d)
              uy (/ (- (cadr c2) (cadr c1)) d)
              a  (/ (+ (* d d) (* r1 r1) (- (* r2 r2))) (* 2.0 d))
              h2 (- (* r1 r1) (* a a)))
        (if (> h2 0.0)
            (progn
              (setq h  (sqrt h2)
                    bx (+ (car c1) (* a ux))
                    by (+ (cadr c1) (* a uy)))
              (list (+ bx (* side h (- uy)))
                    (+ by (* side h ux))))))))

;; 2-D vector sum and scale.
(defun oasis:v+ (a b) (list (+ (car a) (car b)) (+ (cadr a) (cadr b))))
(defun oasis:v* (v s) (list (* (car v) s) (* (cadr v) s)))

;; The unit normal along which two circles share an external tangent
;; line, on the RIGHT of c1->c2 -- the outside of a counter-clockwise
;; ring.  Both tangent points lie along it from their own centre, so a
;; straight run between two bulges is entirely described by it.  When
;; both bulges are tangent to the same bound it comes out perpendicular
;; to that bound, which is what makes a flat bottom flat.  nil when one
;; circle contains the other.
(defun oasis:extnorm (c1 r1 c2 r2 / d ux uy k q)
  (setq d (distance c1 c2))
  (if (> d oasis:*fuzz*)
      (progn
        (setq ux (/ (- (car c2) (car c1)) d)
              uy (/ (- (cadr c2) (cadr c1)) d)
              k  (/ (- r1 r2) d)
              q  (- 1.0 (* k k)))
        (if (> q 0.0)
            (progn
              (setq q (sqrt q))
              ;; k along c1->c2, the rest along the right-hand perpendicular
              (list (+ (* k ux) (* q uy))
                    (- (* k uy) (* q ux))))))))

;; Centre of the circle of radius rf externally tangent to both (c1 r1)
;; and (c2 r2) and lying on the RIGHT of c1->c2.  The bulges are named
;; counter-clockwise round the pool, and a counter-clockwise ring keeps
;; the water on its left, so the right-hand solution is the one outside
;; the pool -- the one whose near side becomes the reverse curve.
(defun oasis:fillet (c1 r1 c2 r2 rf)
  (oasis:circint c1 (+ r1 rf) c2 (+ r2 rf) -1.0))

;; The joiner between two consecutive bulges, as
;;   (kind data angle-out angle-in)
;; where kind is nil for a reverse arc -- data its centre -- or "LINE"
;; for a straight run, data the outward normal along it.  angle-out is
;; where the first bulge hands over, angle-in where the second picks up.
;; nil when the two cannot be joined at all.
(defun oasis:joiner (c1 r1 c2 r2 rf / cf m a)
  (cond
    ;; a SEAM: one circle inside the other, touching -- the internal
    ;; tangency of a kidney's side against its top circle.  The touch
    ;; point lies along the line of centres, so BOTH arcs meet it at the
    ;; same angle -- from the bigger centre towards the smaller -- and
    ;; the outline hands straight over with nothing drawn between.
    ((and (= (type rf) 'STR) (= rf "SEAM"))
     (setq a (if (> r1 r2) (angle c1 c2) (angle c2 c1)))
     (list "SEAM" nil a a))
    (rf
     (setq cf (oasis:fillet c1 r1 c2 r2 rf))
     (if cf (list nil cf (angle c1 cf) (angle c2 cf))))
    (t
     (setq m (oasis:extnorm c1 r1 c2 r2))
     (if m (progn (setq a (atan (cadr m) (car m)))
                  (list "LINE" m a a))))))

;; T when a joiner is a seam.
(defun oasis:seam-p (j)
  (and (= (type (nth 0 j)) 'STR) (= (nth 0 j) "SEAM")))

;; T when a ring element is a straight run rather than an arc.
(defun oasis:line-p (a)
  (and (= (type (nth 5 a)) 'STR) (= (nth 5 a) "LINE")))

;; The smallest tangent radius that can still reach from one bulge to
;; the other.  Zero when the two bulges already overlap, since then any
;; radius reaches.
(defun oasis:filmin (c1 r1 c2 r2)
  (max 0.0 (/ (- (distance c1 c2) r1 r2) 2.0)))

;; T when one bulge circle lies wholly inside the other (or the two are
;; concentric).  No tangent radius can bridge that: raising it grows
;; both circles' reach by the same amount, so they stay nested for ever.
(defun oasis:nested-p (c1 r1 c2 r2)
  (<= (distance c1 c2) (+ (abs (- r1 r2)) oasis:*fuzz*)))

;;; -------------------- kidney geometry ---------------------------------
;;; A kidney is three bulges and ONE reverse arc.  The two side circles
;;; sit inside the big top circle, touching it from within -- an internal
;;; tangency, where the outline hands straight over from one arc to the
;;; other with nothing drawn between.  The bottom is the ordinary
;;; external fillet.  What is given and what is derived depends on which
;;; kidney it is:
;;;
;;;   TrueKidney   the TOP-CENTER radius is given; the two sides come out
;;;                equal, derived from having to touch it.  The top
;;;                circle is tangent to the Y-max bound, centred.
;;;   AsymKidney   the two SIDE radii are given, unequal; the top circle
;;;                is derived -- tangent to the Y-max bound and touching
;;;                both sides from outside them, its centre landing
;;;                wherever those three contacts put it.

;; The smallest top-center radius a true kidney can take: the circle
;; through the two bottom corners tangent to the top bound -- where the
;; matching sides shrink to nothing.
(defun oasis:ktrue-min (w h)
  (+ (/ h 2.0) (/ (* w w) (* 8.0 h))))

;; The matching side radius a true kidney derives from its top circle,
;; or nil.  The discriminant is exactly 4(2R-w)(2R-h), so any R past
;; oasis:ktrue-min has one.
(defun oasis:ktrue-side (w h rt / b c disc r)
  (setq b    (+ w (* 2.0 h) (* -4.0 rt))
        c    (+ (/ (* w w) 4.0) (* (- h rt) (- h rt)) (- (* rt rt)))
        disc (- (* b b) (* 4.0 c)))
  (if (>= disc 0.0)
      (progn
        (setq r (/ (+ b (sqrt disc)) 2.0))
        (if (> r oasis:*fuzz*) r))))

;; The asymmetric kidney's top circle: tangent to the Y-max bound and
;; internally tangent to both given sides.  Eliminating its radius from
;; the two tangency equations leaves a quadratic in its centre's X; a
;; root is legal when the circle contains both sides and the point where
;; it touches the top bound lies ON the arc between the two seams --
;; that arc is the drawn top, so the touch must be on it.  Of the legal
;; roots the one nearest the middle wins.  Returns (cx R) or nil.
(defun oasis:kidney-top (w h rl rr
                         / sl sr a1 a2 b1 b2 qa qb qc d sd roots cx rt
                           ty al ar sw best bin cin)
  (setq sl (float rl)
        sr (- w rr)
        a1 (- h (* 2.0 rl))
        a2 (- h (* 2.0 rr))
        b1 (+ (* sl sl) (* (- h rl) (- h rl)) (- (* rl rl)))
        b2 (+ (* sr sr) (* (- h rr) (- h rr)) (- (* rr rr)))
        qa (- a2 a1)
        qb (* -2.0 (- (* sl a2) (* sr a1)))
        qc (- (* a2 b1) (* a1 b2))
        roots nil)
  (if (< (abs qa) oasis:*fuzz*)
      (if (> (abs qb) oasis:*fuzz*)
          (setq roots (list (/ (- qc) qb))))
      (progn
        (setq d (- (* qb qb) (* 4.0 qa qc)))
        (if (>= d 0.0)
            (setq sd    (sqrt d)
                  roots (list (/ (+ (- qb) sd) (* 2.0 qa))
                              (/ (- (- qb) sd) (* 2.0 qa)))))))
  (setq best nil)
  (foreach cx roots
    (setq rt (cond ((> (abs a1) oasis:*fuzz*)
                    (/ (+ (* cx cx) (* -2.0 sl cx) b1) (* 2.0 a1)))
                   ((> (abs a2) oasis:*fuzz*)
                    (/ (+ (* cx cx) (* -2.0 sr cx) b2) (* 2.0 a2)))))
    (if (and rt (> rt (+ (max rl rr) oasis:*fuzz*)))
        (progn
          (setq ty (- h rt)
                al (angle (list cx ty) (list sl rl))
                ar (angle (list cx ty) (list sr rr))
                sw (cal:angnorm (- al ar)))
          (if (<= (cal:angnorm (- (/ pi 2.0) ar)) sw)
              (progn
                (setq cin (and (<= sl cx) (<= cx sr)))
                (if (or (null best)
                        (and cin (not (nth 2 best)))
                        (and (eq cin (nth 2 best))
                             (< (abs (- cx (/ w 2.0))) (abs (- (car best) (/ w 2.0))))))
                    (setq best (list cx rt cin))))))))
  (if best (list (car best) (cadr best))))

;; The outline, in the counter-clockwise order it runs round the pool.
;; Each element comes back as
;;
;;     (name centre radius start end kind slot)
;;
;; with the angles in RADIANS ready for an ARC entity's group 50 / 51.
;; kind is T for a bulge, nil for a reverse arc, and "LINE" for a
;; straight run -- on which centre and radius hold the run's two ends
;; instead, and start holds the direction out of the pool.  slot is the
;; answer the radius came from, or nil where the envelope pinned it.
;;
;; Bulges land at the even positions and joiners at the odd ones, for
;; every shape: six elements for the three-bulge oasis shapes, four for
;; the two-bulge clouds.  nil when a joiner does not exist -- c:OASIS
;; checks for that before it ever gets here, so a nil return means an
;; input slipped past the checks, not a user mistake.
(defun oasis:solve (w h rl rt rr ftl ftr fbc variant
                    / nm bc br bs jr js kt n i j js2 jj ok jp jn out)
  (setq nm (oasis:names variant) ok T)
  (cond
    ((oasis:cloud-p variant)
     (setq rl (oasis:leftrad variant h rl)
           bc (list (list rl rl) (list (- w rr) rr))
           br (list rl rr)
           bs (list nil 6)
           jr (list (if (= variant "StraightBottom") nil fbc) ftl)
           js (list 9 7)))
    ((oasis:kidney-p variant)
     ;; the sides or the top come DERIVED, whichever the shape did not
     ;; ask for -- and when the derivation has no answer there is no
     ;; kidney to build
     (if (= variant "TrueKidney")
         (setq rl (oasis:ktrue-side w h rt)
               rr rl
               kt (if rl (list (* 0.5 w) rt)))
         (setq kt (oasis:kidney-top w h rl rr)))
     (if (and rl rr kt)
         (setq bc (list (list rl rl) (list (- w rr) rr)
                        (list (car kt) (- h (cadr kt))))
               br (list rl rr (cadr kt))
               bs (if (= variant "TrueKidney")
                      (list nil nil 5)
                      (list 4 6 nil))
               jr (list fbc "SEAM" "SEAM")
               js (list 9 nil nil))
         (setq ok nil br '())))
    (t
     (setq bc (list (list rl rl) (list (- w rr) rr)
                    (oasis:topcen w h rt variant))
           br (list rl rr rt)
           bs (list 4 6 5)
           jr (list fbc ftr ftl)
           js (list 9 8 7))))
  (setq n (length br) i 0 js2 nil)
  (while (< i n)
    (setq j  (rem (1+ i) n)
          jj (oasis:joiner (nth i bc) (nth i br) (nth j bc) (nth j br)
                           (nth i jr)))
    (if jj (setq js2 (cons jj js2)) (setq ok nil))
    (setq i (1+ i)))
  (setq js2 (reverse js2))
  (if ok
      (progn
        (setq i 0 out nil)
        (while (< i n)
          (setq j  (rem (1+ i) n)
                jp (nth (rem (+ i n -1) n) js2)   ; the joiner before it
                jn (nth i js2)                    ; and the one after
                ;; the bulge: from where the joiner before it hands over
                ;; to where the joiner after it picks up
                out (cons (list (nth (* 2 i) nm) (nth i bc) (nth i br)
                                (nth 3 jp) (nth 2 jn) T (nth i bs))
                          out)
                ;; then that joiner.  A seam draws nothing -- the two
                ;; arcs hand straight over at the touch point.  A reverse
                ;; arc curves the other way round its own circle, so its
                ;; two ends swap over.
                out (cond
                      ((oasis:seam-p jn) out)
                      ((and (= (type (nth 0 jn)) 'STR)
                            (= (nth 0 jn) "LINE"))
                       (cons (list (nth (1+ (* 2 i)) nm)
                                   (oasis:v+ (nth i bc)
                                             (oasis:v* (nth 1 jn) (nth i br)))
                                   (oasis:v+ (nth j bc)
                                             (oasis:v* (nth 1 jn) (nth j br)))
                                   (nth 2 jn) nil "LINE" nil)
                             out))
                      (t
                       (cons (list (nth (1+ (* 2 i)) nm) (nth 1 jn)
                                   (nth i jr)
                                   (angle (nth 1 jn) (nth j bc))
                                   (angle (nth 1 jn) (nth i bc))
                                   nil (nth i js))
                             out)))
                i   (1+ i)))
        (reverse out))))

;; Note an overrun of AMOUNT past SIDE by arc NM, keeping the worst one
;; seen for that side.  Anything within the fuzz is not an overrun.
(defun oasis:worst (lst side amount nm / p out hit)
  (if (<= amount oasis:*fuzz*)
      lst
      (progn
        (setq out nil hit nil)
        (foreach p lst
          (if (= (car p) side)
              (setq hit T
                    out (cons (if (> amount (cadr p)) (list side amount nm) p)
                              out))
              (setq out (cons p out))))
        (if hit (reverse out) (cons (list side amount nm) lst)))))

;; How far the outline reaches past each bound of the envelope, and which
;; arc takes it there.  Every arc end and the compass point of every
;; quadrant a sweep crosses is tested -- between them they hold every
;; extreme the outline has -- so the report can name the arc that is out
;; instead of guessing at the radius behind it.  Returns a list of
;; (side amount arc-name), only for bounds that are really broken.
(defun oasis:overruns (arcs w h / over a c r s sw k ang p nm)
  (setq over nil)
  (foreach a arcs
    (setq nm (nth 0 a)
          c  (nth 1 a)
          r  (nth 2 a)
          s  (nth 3 a)
          sw (if (oasis:line-p a) 0.0 (cal:angnorm (- (nth 4 a) s)))
          k  -2)
    (while (< k (if (oasis:line-p a) 0 4))
      (setq ang (cond ((= k -2) s)
                      ((= k -1) (nth 4 a))
                      (t (* k (/ pi 2.0)))))
      (if (or (minusp k) (<= (cal:angnorm (- ang s)) sw))
          (setq p    (if (oasis:line-p a)
                         (nth (if (= k -2) 1 2) a)   ; its two ends
                         (polar c ang r))
                over (oasis:worst over "the left"   (- 0.0 (car p)) nm)
                over (oasis:worst over "the bottom" (- 0.0 (cadr p)) nm)
                over (oasis:worst over "the right"  (- (car p) w) nm)
                over (oasis:worst over "the top"    (- (cadr p) h) nm)))
      (setq k (1+ k))))
  over)

;; T when the angle ANG falls inside ARC's counter-clockwise sweep.
(defun oasis:on-arc-p (a ang)
  (<= (cal:angnorm (- ang (nth 3 a)))
      (cal:angnorm (- (nth 4 a) (nth 3 a)))))

;; The pairs of arcs that run through each other.  Neighbours are
;; externally tangent by construction and touch only at the end they
;; share, so they are skipped; anything else that meets is the outline
;; crossing itself.  Exact rather than sampled: two circles meet in at
;; most two points, and a crossing is one of those points lying inside
;; BOTH sweeps -- nine pairs, eighteen points, and no curve to walk on
;; the six-element shapes.  A straight run is skipped: it lies along a
;; bound with both its bulges tangent to that bound, so nothing can reach
;; it without leaving the envelope first, which the extents report
;; already names.
(defun oasis:crossings (arcs / n i j a b p side pair out)
  (setq n (length arcs) i 0 out nil)
  (while (< i n)
    (setq j (1+ i))
    (while (< j n)
      (if (not (or (= j (1+ i)) (and (= i 0) (= j (1- n)))
                   (oasis:line-p (nth i arcs))
                   (oasis:line-p (nth j arcs))))
        (progn
          (setq a    (nth i arcs)
                b    (nth j arcs)
                pair (list (nth 0 a) (nth 0 b)))
          (foreach side '(1.0 -1.0)
            (setq p (oasis:circint (nth 1 a) (nth 2 a)
                                   (nth 1 b) (nth 2 b) side))
            (if (and p
                     (not (member pair out))
                     (oasis:on-arc-p a (angle (nth 1 a) p))
                     (oasis:on-arc-p b (angle (nth 1 b) p)))
              (setq out (cons pair out))))))
      (setq j (1+ j)))
    (setq i (1+ i)))
  (reverse out))

;;; -------------------- the drawing frame --------------------------------
;;; The pool is laid out in the CURRENT UCS, so it lines up with the way
;;; the user is working, and the dimension commands -- which read their
;;; points in the UCS -- need no conversion at all.  An ARC entity is the
;;; awkward one: its centre is stored in WORLD coordinates and its start
;;; and end angles are measured from the WORLD X axis, so both have to be
;;; carried across on the way into entmake.  Mixing the two frames is how
;;; a pool ends up detached from its own dimensions.
;;;
;;; A UCS tilted out of the world plan cannot be carried this way -- each
;;; arc would need an extrusion of its own -- so c:OASIS refuses to run
;;; in one rather than draw something wrong.

;; T when the current UCS lies flat in the world plan, i.e. its Z axis is
;; parallel to the world Z.  Every plan-drafting UCS is.
(defun oasis:ucs-flat-p ( / z)
  (setq z (trans '(0.0 0.0 1.0) 1 0 T))
  (< (abs (- (abs (caddr z)) 1.0)) 1.0e-8))

;; How far the current UCS is turned from the world X axis.  Read off the
;; components rather than with (angle ...), which projects onto the UCS
;; plane and would answer zero however far the UCS is turned.
(defun oasis:ucsang ( / x)
  (setq x (trans '(1.0 0.0 0.0) 1 0 T))
  (atan (cadr x) (car x)))

;;; -------------------- drawing -----------------------------------------

;; A point in pool coordinates moved to where the pool is being drawn.
;; The result is a point in the current UCS, at the base point's own
;; elevation -- which is what the dimension commands want; oasis:draw
;; converts it for entmake.
(defun oasis:wp (p base)
  (list (+ (car p) (car base))
        (+ (cadr p) (cadr base))
        (caddr base)))

;; The six arcs, drawn in the order they run round the pool.  Returns
;; their entity names in that same order, so the radius dimensions can
;; hook onto them afterwards.
(defun oasis:draw (arcs base lay / out a rot)
  (setq out nil
        rot (oasis:ucsang))       ; UCS -> world, for the angles
  (foreach a arcs
    (if (oasis:line-p a)
        (entmake (list '(0 . "LINE")
                       (cons 8 lay)
                       (cons 10 (trans (oasis:wp (nth 1 a) base) 1 0))
                       (cons 11 (trans (oasis:wp (nth 2 a) base) 1 0))))
        (entmake (list '(0 . "ARC")
                       (cons 8 lay)
                       (cons 10 (trans (oasis:wp (nth 1 a) base) 1 0))
                       (cons 40 (nth 2 a))
                       (cons 50 (cal:angnorm (+ (nth 3 a) rot)))
                       (cons 51 (cal:angnorm (+ (nth 4 a) rot))))))
    (setq out (cons (entlast) out)))
  (reverse out))

;; How far off the pool the dimensions sit.  POOL's rule, so an oasis
;; drawn beside a rectangle is dimensioned at the same stand-off.
(defun oasis:dimoff (w h)
  (max 12.0 (/ (max w h) 18.0)))

;; The midpoint of an arc, and the direction out of the pool there.
;; On a bulge that is away from the centre; on a reverse arc it is
;; towards it, because a reverse arc's centre is itself outside the
;; pool.  Either way the radius dimension is dragged clear of the water.
;; Returns (midpoint . outward-angle).
(defun oasis:arcmid (a / c r s w m)
  (if (oasis:line-p a)
      ;; halfway along it, and straight out of the pool across it
      (cons (list (* 0.5 (+ (car (nth 1 a)) (car (nth 2 a))))
                  (* 0.5 (+ (cadr (nth 1 a)) (cadr (nth 2 a)))))
            (nth 3 a))
      (progn
        (setq c (nth 1 a)
              r (nth 2 a)
              s (nth 3 a)
              w (cal:angnorm (- (nth 4 a) s))
              m (polar c (cal:angnorm (+ s (/ w 2.0))) r))
        (cons m (if (nth 5 a) (angle c m) (angle m c))))))

;; Overall X, overall Y, and a radius on each of the six arcs.  The two
;; overall dimensions are hooked to the points that actually touch the
;; envelope -- the left and right bulges' outermost points for X, the
;; top bulge's highest point and the left bulge's lowest for Y -- so
;; they measure the bounds the user was asked for, not a chord of them.
(defun oasis:dimension (arcs ents base w h lay / doff i a e md yl yr top)
  (setvar "CLAYER" lay)
  (oasis:dimstyle-on oasis:*dimstyle*)
  (setq doff (oasis:dimoff w h)
        ;; the ring starts at the left bulge and the right bulge is two
        ;; along, on every shape; each touches its own bound level with
        ;; its centre, so those are the points the overall X hooks
        yl   (cadr (nth 1 (nth 0 arcs)))
        yr   (cadr (nth 1 (nth 2 arcs)))
        ;; and the overall Y hooks the bulge that actually reaches the
        ;; top bound -- the one whose centre plus radius lands on it
        top  (nth 0 arcs))
  (foreach a arcs
    (if (and (not (oasis:line-p a))
             (nth 5 a)
             (> (+ (cadr (nth 1 a)) (nth 2 a))
                (+ (cadr (nth 1 top)) (nth 2 top))))
        (setq top a)))
  (command "_.DIMLINEAR"
           (oasis:wp (list 0.0 yl) base)
           (oasis:wp (list w yr) base)
           "_H"
           (oasis:wp (list (* 0.5 w) (+ h doff)) base))
  (command "_.DIMLINEAR"
           (oasis:wp (list (car (nth 1 top)) h) base)
           (oasis:wp (list yl 0.0) base)
           "_V"
           (oasis:wp (list (- 0.0 doff) (* 0.5 h)) base))
  ;; walked by index so each arc keeps the entity oasis:draw made for it
  (setq i 0)
  (while (< i (length arcs))
    (setq a  (nth i arcs)
          e  (nth i ents)
          md (oasis:arcmid a)
          i  (1+ i))
    (cond
      ((null e))
      ;; a straight run has no radius to call out; its LENGTH is the
      ;; measurement that matters, so it gets an aligned dim instead
      ((oasis:line-p a)
       (command "_.DIMALIGNED"
                (oasis:wp (nth 1 a) base) (oasis:wp (nth 2 a) base)
                (oasis:wp (polar (car md) (cdr md) (* 0.9 doff)) base)))
      (t
       (command "_.DIMRADIUS"
                (list e (oasis:wp (car md) base))
                (oasis:wp (polar (car md) (cdr md) (* 0.9 doff)) base)))))
  (princ))

;;; -------------------- the check drawing --------------------------------
;;; A second copy of the pool, off to the right, dimensioned the way a
;;; layout is checked rather than the way it is built: every circle
;;; centre tied back to the two envelope corners nearest it, and every
;;; pair of neighbouring centres tied to each other.  Between them those
;;; two families pin all six centres against the box and against one
;;; another, so a transcription slip in any single radius shows up as a
;;; dimension that does not agree with the order sheet.
;;;
;;; The centre-to-centre ties have a second use: neighbouring circles are
;;; externally tangent by construction, so each of those dimensions must
;;; read exactly the sum of the two radii.  Anything else means the
;;; outline is not tangent-continuous.

;; The two envelope corners nearest point P, nearest first.
(defun oasis:near2 (p w h / corners c best rest d bd rd)
  (setq corners (list (list 0.0 0.0) (list w 0.0)
                      (list w h) (list 0.0 h))
        best nil rest nil bd nil rd nil)
  (foreach c corners
    (setq d (distance p c))
    (cond ((or (null bd) (< d bd)) (setq rest best rd bd best c bd d))
          ((or (null rd) (< d rd)) (setq rest c rd d))))
  (list best rest))

;; Add a tie between two centres unless it is already there.  A pair of
;; bulges that happen to be ring neighbours as well would otherwise be
;; dimensioned twice, one dim on top of the other.
(defun oasis:addtie (ties p q / e hit)
  (setq hit nil)
  (foreach e ties
    (if (or (and (equal (car e) p 1e-8) (equal (cadr e) q 1e-8))
            (and (equal (car e) q 1e-8) (equal (cadr e) p 1e-8)))
        (setq hit T)))
  (if hit ties (append ties (list (list p q)))))

;; One cross dimension between two drawn points, its dimension line
;; sitting on the line it measures -- the look POOL and CDCREATE give a
;; tie measurement.
(defun oasis:crossdim (p q base)
  (command "_.DIMALIGNED"
           (oasis:wp p base) (oasis:wp q base)
           (oasis:wp (list (* 0.5 (+ (car p) (car q)))
                           (* 0.5 (+ (cadr p) (cadr q))))
                     base)))

;; The whole check drawing, placed at CBASE.  Returns nothing; the caller
;; has already put the layers and the dim style in place.
(defun oasis:checkdraw (arcs cbase w h lt / mark cens bul ties a e i n near)
  (oasis:dimstyle-on oasis:*crossstyle*)
  (setvar "CLAYER" oasis:*guidelayer*)
  (oasis:pv-box w h cbase lt)
  (setq mark (max 1.0 (/ (max w h) 90.0)))
  ;; the outline itself, so the centres have something to belong to
  (oasis:draw arcs cbase oasis:*poollayer*)
  (setvar "CLAYER" oasis:*guidelayer*)
  ;; every circle centre in ring order, and the BULGE centres again on
  ;; their own.  A straight run has no centre, so it drops out of both
  ;; and the ring closes over it.
  (setq cens nil bul nil)
  (foreach a arcs
    (if (not (oasis:line-p a))
        (progn
          (setq cens (cons (nth 1 a) cens))
          (if (nth 5 a) (setq bul (cons (nth 1 a) bul))))))
  (setq cens (reverse cens)
        bul  (reverse bul)
        n    (length cens)
        i    0)
  (while (< i n)
    (oasis:pv-circle (nth i cens) mark cbase "CONTINUOUS" nil)
    (setq i (1+ i)))
  (setvar "CLAYER" oasis:*dimlayer*)
  ;; every centre back to the two corners nearest it
  (setq i 0)
  (while (< i n)
    (setq near (oasis:near2 (nth i cens) w h))
    (oasis:crossdim (nth i cens) (car near) cbase)
    (oasis:crossdim (nth i cens) (cadr near) cbase)
    (setq i (1+ i)))
  ;; then the ties between centres: each circle to the next one round the
  ;; ring, AND each bulge to the next bulge.  The ring ties check the
  ;; tangency -- neighbours are externally tangent, so each of those must
  ;; read the two radii added together -- and the bulge ties check the
  ;; lobes against each other, across whatever sits between them.
  (setq ties nil i 0)
  (while (< i n)
    (setq ties (oasis:addtie ties (nth i cens) (nth (rem (1+ i) n) cens))
          i    (1+ i)))
  (setq i 0)
  (while (< i (length bul))
    (setq ties (oasis:addtie ties (nth i bul)
                             (nth (rem (1+ i) (length bul)) bul))
          i    (1+ i)))
  (foreach e ties (oasis:crossdim (car e) (cadr e) cbase))
  (+ (* 2 n) (length ties)))

;; Where the check drawing goes: clear to the right of the pool and of
;; the radius dimensions on that side.
(defun oasis:checkbase (base w h)
  (list (+ (car base) w (* oasis:*checkgap* (oasis:dimoff w h)))
        (cadr base)
        (caddr base)))

;;; -------------------- the live preview ---------------------------------
;;; Every question redraws the pool as it stands, so the answer being
;;; typed can be seen landing.  Three things overlap on purpose:
;;;
;;;   * the OUTLINE, solid, on the pool layer -- what will actually be
;;;     drawn;
;;;   * each circle it is cut from, DASHED, on the guide layer -- the
;;;     construction behind the outline, so the radius being asked for
;;;     has something to belong to;
;;;   * a label on every circle: its radius once given, "?" until then.
;;;
;;; The circle the question is about -- its dashed circle, its arc and
;;; its label -- is drawn red, so there is never a doubt about which
;;; radius is being asked for.
;;;
;;; A radius that has not been answered yet still needs a value for any
;;; of this to be drawable, so the preview fills the gaps in with
;;; provisional ones (oasis:fillin) and marks every one it invented with
;;; a "?".  If a provisional set happens not to solve, the outline is
;;; simply left out and the circles and box still show.

;; The answers so far, with the gaps filled in well enough to draw.
;;
;; The provisionals are not arbitrary: they are the proportions an oasis
;; usually comes in, so the shape on screen at the first question is
;; already close to the one being measured rather than something the
;; draftsman has to look past.  A side bulge spans about three quarters
;; of the short bound and the top bulge about half the long one --
;; oasis:*startside* and oasis:*starttop* are those two fractions, and
;; they are HALVED here because a bulge is twice its radius across.  On a
;; 40 x 20 that is 7'-6" side bulges and a 10'-0" top, against the 8'/9'
;; and 11' of the drawing this tool was written from.
;;
;; A tangent radius has no such rule of thumb -- what looks right depends
;; entirely on the three bulges -- so it takes a quarter of the short
;; bound, lifted clear of its own minimum when that is larger.
(defun oasis:fillin (ans / var w h rl rt rr cl ct cr side top g big)
  (setq var  (oasis:variant ans)
        w    (nth 2 ans)
        h    (nth 3 ans))
  (if (oasis:kidney-p var)
      ;; the kidney: what was not asked for is derived by the solver, so
      ;; only the asked slots need filling -- the true one's top circle
      ;; half again over its minimum, the asymmetric one's sides a
      ;; kidney-ish fraction of the short bound, and the bottom off the
      ;; sides the way every joiner is
      (progn
        (setq rt (if (= var "TrueKidney")
                     (cond ((nth 5 ans)) ((* 1.5 (oasis:ktrue-min w h)))))
              rl (if (= var "AsymKidney")
                     (cond ((nth 4 ans)) ((* 0.40 (min w h)))))
              rr (if (= var "AsymKidney")
                     (cond ((nth 6 ans)) ((* 0.45 (min w h)))))
              g  (if (= var "TrueKidney")
                     (cond ((oasis:ktrue-side w h rt)) (48.0))
                     (min rl rr)))
        (list w h rl rt rr nil nil
              (cond ((nth 9 ans)) ((* 0.6 g)))))
      (progn
  (setq side (* 0.5 oasis:*startside* (min w h))
        rl   (cond ((oasis:leftrad var h (nth 4 ans))) (side))
        rr   (cond ((nth 6 ans)) (side))
        ;; the centred bulge is measured across the long bound, the
        ;; corner one across the short -- it has to fit both ways
        rt   (if (oasis:cloud-p var)
                 nil
                 (cond ((nth 5 ans))
                       ((* 0.5 oasis:*starttop*
                           (if (oasis:topfits-p var) (min w h) w)))))
        ;; a joiner is read against the bulges either side of it, not
        ;; against the envelope, so size it off them -- that keeps the
        ;; bulges the bigger circles, which is the point of the picture.
        ;; A cloud's bottom is the exception: it sweeps under the whole
        ;; pool, so it is read off the biggest bulge rather than the
        ;; smallest.
        g    (* 0.6 (min rl rr (cond (rt) (rl))))
        big  (* 1.2 (max rl rr (cond (rt) (rl))))
        cl   (list rl rl)
        ct   (if rt (oasis:topcen w h rt var))
        cr   (list (- w rr) rr))
  (list w h rl rt rr
        (cond ((nth 7 ans))
              ((oasis:cloud-p var) (max g (* 1.25 (oasis:filmin cr rr cl rl))))
              ((max g (* 1.25 (oasis:filmin ct rt cl rl)))))
        (cond ((nth 8 ans))
              ((oasis:cloud-p var) nil)
              ((max g (* 1.25 (oasis:filmin cr rr ct rt)))))
        (cond ((nth 9 ans))
              ((oasis:cloud-p var) (max big (* 1.25 (oasis:filmin cl rl cr rr))))
              ((max g (* 1.25 (oasis:filmin cl rl cr rr)))))))))

;; Erase a preview.  Entities the user has since deleted are skipped, so
;; a stray U in the middle of the questions cannot break the next redraw.
(defun oasis:pv-clear (ents / e)
  (foreach e ents (if (and e (entget e)) (entdel e)))
  nil)

;; One dashed guide entity, red when it is the one being asked about.
(defun oasis:pv-circle (c r base lt hi / lst)
  (setq lst (list '(0 . "CIRCLE")
                  (cons 8 oasis:*guidelayer*)
                  (cons 10 (trans (oasis:wp c base) 1 0))
                  (cons 40 r)))
  (if hi (setq lst (append lst (list (cons 62 oasis:*hicolor*)))))
  (if (/= lt "CONTINUOUS")
      (setq lst (append lst (list (cons 6 lt) (cons 48 (oasis:ltsc))))))
  (entmake lst)
  (entlast))

(defun oasis:pv-line (p q base lt / lst)
  (setq lst (list '(0 . "LINE")
                  (cons 8 oasis:*guidelayer*)
                  (cons 10 (trans (oasis:wp p base) 1 0))
                  (cons 11 (trans (oasis:wp q base) 1 0))))
  (if (/= lt "CONTINUOUS")
      (setq lst (append lst (list (cons 6 lt) (cons 48 (oasis:ltsc))))))
  (entmake lst)
  (entlast))

(defun oasis:pv-text (pt hgt str base hi / lst)
  (setq lst (list '(0 . "TEXT")
                  (cons 8 oasis:*guidelayer*)
                  (cons 10 (trans (oasis:wp pt base) 1 0))
                  (cons 11 (trans (oasis:wp pt base) 1 0))
                  (cons 40 hgt)
                  (cons 72 1)                 ; centred on the point
                  (cons 1 str)))
  (if hi (setq lst (append lst (list (cons 62 oasis:*hicolor*)))))
  (entmake lst)
  (entlast))

;; The envelope box, dashed -- the bounds the pool is being fitted to.
(defun oasis:pv-box (w h base lt / out)
  (setq out (list (oasis:pv-line (list 0.0 0.0) (list w 0.0) base lt)
                  (oasis:pv-line (list w 0.0) (list w h) base lt)
                  (oasis:pv-line (list w h) (list 0.0 h) base lt)
                  (oasis:pv-line (list 0.0 h) (list 0.0 0.0) base lt)))
  out)

;; Redraw the preview for the question about answer slot K, and hand back
;; the entities it made, ready to be passed to the next call so they can
;; be cleared first.  Nothing is drawn until the shape, the base point
;; and both bounds are known -- before that there is no envelope to draw
;; anything inside.
(defun oasis:preview (old ans k
                      / var base w h full arcs lt out ring n i a md txt
                        hgt slot hi)
  (oasis:pv-clear old)
  (setq var  (oasis:variant ans)
        base (nth 1 ans)
        w    (nth 2 ans)
        h    (nth 3 ans)
        out  nil)
  (if (and var base w h)
      (progn
        (cal:osdown)
        (setq lt   (oasis:dashlt w h)
              hgt  (/ (max w h) 28.0)
              full (oasis:fillin ans)
              arcs (oasis:solve (nth 0 full) (nth 1 full) (nth 2 full)
                                (nth 3 full) (nth 4 full) (nth 5 full)
                                (nth 6 full) (nth 7 full) var)
              out  (oasis:pv-box w h base lt))
        (if arcs
            (progn
              ;; the outline, solid, and behind it the circle each arc is
              ;; cut from, dashed; the one being asked about goes red
              (setq ring (oasis:draw arcs base oasis:*poollayer*)
                    out  (append out ring)
                    n    (length arcs)
                    i    0)
              (while (< i n)
                (setq a    (nth i arcs)
                      slot (nth 6 a)
                      hi   (and slot (= slot k))
                      md   (oasis:arcmid a))
                (if hi (oasis:recolor (nth i ring) oasis:*hicolor*))
                ;; a straight run has no circle behind it and no radius
                ;; to label -- the envelope box already shows its bound
                (if (not (oasis:line-p a))
                    (setq out (cons (oasis:pv-circle (nth 1 a) (nth 2 a)
                                                     base lt hi)
                                    out)
                          txt (if (and slot (nth slot ans))
                                  (rtos (nth slot ans))
                                  (if slot "?" (rtos (nth 2 a))))
                          out (cons (oasis:pv-text
                                      (polar (car md) (cdr md) (* 1.7 hgt))
                                      hgt txt base hi)
                                    out)))
                (setq i (1+ i)))))
        (cal:osup)))
  out)

;; Force an entity's colour, for the one arc a question is about.
(defun oasis:recolor (e col / ed)
  (if (and e (setq ed (entget e)))
      (entmod (if (assoc 62 ed)
                  (subst (cons 62 col) (assoc 62 ed) ed)
                  (append ed (list (cons 62 col)))))))

;;; -------------------- the questions -----------------------------------

;; lst with slot k replaced by v.  The answer list keeps its length, so
;; a Back and a re-answer overwrite in place instead of growing it.
(defun oasis:put (lst k v / i out e)
  (setq i 0 out nil)
  (foreach e lst
    (setq out (cons (if (= i k) v e) out)
          i   (1+ i)))
  (reverse out))

;; Where the pool goes.  Picked with the user's own object snaps still
;; live, and backed out of like any other question -- nothing has been
;; drawn at that point.  Enter takes the origin.  Returns a 3-D point
;; (the elevation is carried, so a UCS with one is honoured) or
;; OASIS-BACK.
(defun oasis:askbase (back / v)
  (if back (initget "Back Undo"))
  (setq v (getpoint (strcat "\nInsertion base point <0,0>"
                            (if back " [Back]" "") ": ")))
  (cond ((and (= (type v) 'STR) (member v '("Back" "Undo"))) 'CAL-BACK)
        ((null v) (list 0.0 0.0 0.0))
        (t (list (car v) (cadr v) (if (caddr v) (caddr v) 0.0)))))

;; A side bulge's radius, re-asked until it fits inside the Y bound.
;; A bulge is tangent to the bottom edge, so its top sits at twice its
;; radius: any more than half the Y bound and it breaks out of the top.
(defun oasis:ask-bulge (msg side w h / v)
  (setq v (cal:askdist 'REQ msg nil T))
  (while (and (not (eq v 'CAL-BACK))
              (or (> (* 2.0 v) (+ h oasis:*fuzz*))
                  (> (* 2.0 v) (+ w oasis:*fuzz*))))
    (if (> (* 2.0 v) (+ h oasis:*fuzz*))
        (princ (strcat "\nA " (rtos v) " " side " bulge stands "
                       (rtos (* 2.0 v)) " tall and breaks out through the"
                       " top of a " (rtos h) " envelope.  "
                       (rtos (/ h 2.0)) " or less."))
        (princ (strcat "\nA " (rtos v) " " side " bulge is "
                       (rtos (* 2.0 v)) " across and breaks out through the"
                       " far side of a " (rtos w) " envelope.  "
                       (rtos (/ w 2.0)) " or less.")))
    (setq v (cal:askdist 'REQ msg nil T)))
  v)

;; The top bulge's radius, re-asked while it swallows a side bulge (or
;; is swallowed by one).  Nesting cannot be cured with a tangent radius
;; later, so it has to be caught here.
(defun oasis:ask-top (msg w h rl variant / v cl ct big)
  (setq cl (list rl rl)
        v  (cal:askdist 'REQ msg nil T))
  (while (and (not (eq v 'CAL-BACK))
              (progn
                (setq ct  (oasis:topcen w h v variant)
                      big (and (oasis:topfits-p variant)
                               (> (* 2.0 v) (+ (min w h) oasis:*fuzz*))))
                (or big (oasis:nested-p ct v cl rl))))
    (if big
        ;; only the corner bulge can do this: it is tangent to two
        ;; bounds, so it is twice its radius both ways
        (princ (strcat "\nA " (rtos v) " corner bulge is " (rtos (* 2.0 v))
                       " both ways and breaks out of a " (rtos w) " x "
                       (rtos h) " envelope.  " (rtos (/ (min w h) 2.0))
                       " or less."))
        (princ (strcat "\nA " (rtos v) " top bulge and the left bulge lie one"
                       " inside the other, so no tangent radius can join them"
                       " -- raising one raises the other's reach by just as"
                       " much.  Try a top radius nearer the left bulge's "
                       (rtos rl) ".")))
    (setq v (cal:askdist 'REQ msg nil T)))
  v)

;; A true kidney's top-center radius, re-asked until a kidney can be
;; built on it.  Below a minimum the top circle cannot reach both sides
;; -- at the minimum it passes through the two bottom corners and the
;; matching sides shrink to nothing -- and on a tall narrow envelope a
;; radius can be so big the derived sides meet in the middle.
(defun oasis:ask-ktop (msg w h / v r bad)
  (setq v (cal:askdist 'REQ msg nil T))
  (while (and (not (eq v 'CAL-BACK))
              (progn
                (setq r   (if (> v (+ (oasis:ktrue-min w h) oasis:*fuzz*))
                              (oasis:ktrue-side w h v))
                      bad (cond ((null r) "small")
                                ((> (* 2.0 r) (+ w oasis:*fuzz*)) "big")))
                bad))
    (if (= bad "small")
        (princ (strcat "\nA " (rtos v) " top circle cannot reach both"
                       " sides of a " (rtos w) " x " (rtos h)
                       " envelope -- it has to be more than "
                       (rtos (oasis:ktrue-min w h)) "."))
        (princ (strcat "\nA " (rtos v) " top circle makes the matching"
                       " sides " (rtos r) " each -- " (rtos (* 2.0 r))
                       " across together, more than the " (rtos w)
                       " envelope.  Smaller keeps them apart.")))
    (setq v (cal:askdist 'REQ msg nil T)))
  v)

;; A tangent radius, re-asked until it is big enough to span its two
;; bulges.  Below the minimum the two circles it would have to touch
;; never meet, and there is no such arc at any position.
(defun oasis:ask-tangent (msg c1 r1 c2 r2 / v mn)
  (setq mn (oasis:filmin c1 r1 c2 r2)
        v  (cal:askdist 'REQ msg nil T))
  (while (and (not (eq v 'CAL-BACK))
              (<= v (+ mn oasis:*fuzz*)))
    (princ (strcat "\n" (rtos v) " is too short to reach from one bulge"
                   " to the other -- it has to be more than "
                   (rtos mn) "."))
    (setq v (cal:askdist 'REQ msg nil T)))
  v)

;; One question of the run.  k is the answer slot it fills, ans the
;; answers gathered so far -- the checks that need an earlier answer read
;; it from there, so backing up and changing one re-checks everything
;; after it.  Returns the answer, or OASIS-BACK.
;;
;;   0 which shape      3 Y bound         6 right bulge   8 joiner right
;;   1 base point       4 left bulge      7 joiner top    9 joiner bottom
;;   2 X bound          5 top bulge                      10 a cloud's bottom
;;
;; A shape asks only the slots oasis:steps lists for it.
(defun oasis:askstep (k ans / var v w h rl rt rr cl ct cr)
  (setq var (oasis:variant ans)
        w   (nth 2 ans) h  (nth 3 ans)
        rl  (oasis:leftrad var h (nth 4 ans))
        rt  (nth 5 ans) rr (nth 6 ans))
  ;; a true kidney's sides are derived from its top circle, so by the
  ;; time the bottom joiner is asked for they are known without ever
  ;; having been asked about
  (if (and (= var "TrueKidney") w h rt)
      (setq rl (oasis:ktrue-side w h rt)
            rr rl))
  (setq cl  (if (and w h rl) (list rl rl))
        ct  (if (and w h rt (not (oasis:kidney-p var)))
                (oasis:topcen w h rt var))
        cr  (if (and w h rr) (list (- w rr) rr)))
  (cond
    ;; CLoud takes two capitals because Center already has the C.  The
    ;; keyword comes back spelled that way, so it is normalized here and
    ;; nothing downstream ever sees it.
    ((= k 0)
     (setq v (cal:askkw "Which shape is it?"
                          "Center TopRight CLoud Kidney"
                          "Center/TopRight/CLoud/Kidney" "Center" nil))
     (if (= v "CLoud") "Cloud" v))
    ((= k 10)
     (if (= (nth 0 ans) "Kidney")
         (cal:askkw "Kidney type?" "True Asymmetric"
                      "True/Asymmetric" "True" T)
         (cal:askkw "Cloud bottom?" "Straight Rounded"
                      "Straight/Rounded" "Straight" T)))
    ((= k 1) (oasis:askbase T))
    ((= k 2) (cal:askdist 'REQ "X - overall left-to-right bounds" nil T))
    ((= k 3) (cal:askdist 'REQ "Y - overall front-to-back bounds" nil T))
    ((= k 4) (oasis:ask-bulge (oasis:sprompt var 4) "left" w h))
    ((= k 5) (if (oasis:kidney-p var)
                 (oasis:ask-ktop (oasis:sprompt var 5) w h)
                 (oasis:ask-top (oasis:sprompt var 5) w h rl var)))
    ((= k 6) (oasis:ask-bulge (oasis:sprompt var 6) "right" w h))
    ;; on a cloud the top joiner runs straight from the right bulge back
    ;; to the left one; on an oasis it stops at the third bulge first
    ((= k 7) (if (oasis:cloud-p var)
                 (oasis:ask-tangent (oasis:sprompt var 7) cr rr cl rl)
                 (oasis:ask-tangent (oasis:sprompt var 7) ct rt cl rl)))
    ((= k 8) (oasis:ask-tangent (oasis:sprompt var 8) cr rr ct rt))
    ((= k 9) (oasis:ask-tangent (oasis:sprompt var 9) cl rl cr rr))))

;; The right bulge is the last of the three, so it is the one that has
;; to be checked against BOTH of the others before the tangent radii are
;; asked for.  Returns the name of the bulge it nests with, or nil.
(defun oasis:right-nests (w h rl rt rr variant / cl ct cr)
  (setq rl (oasis:leftrad variant h rl)
        cl (list rl rl)
        cr (list (- w rr) rr))
  (cond ((oasis:nested-p cr rr cl rl) "left")
        ((oasis:cloud-p variant) nil)
        ((progn (setq ct (oasis:topcen w h rt variant))
                (oasis:nested-p cr rr ct rt))
         "top")))

;;; -------------------- reporting ---------------------------------------

;; s padded out to w characters, so the report's rows line up.
(defun oasis:pad (s w)
  (while (< (strlen s) w) (setq s (strcat s " ")))
  s)


;; Say when the outline runs through itself.  Nothing that gets this far
;; was impossible to build -- every arc exists and the six of them close
;; -- but radii wildly out of proportion with each other can send one arc
;; clean through another, and that is not a pool.  It is drawn anyway and
;; named, so it is obvious on the screen and one U takes it away.
(defun oasis:report-crossings (arcs / bad p)
  (setq bad (oasis:crossings arcs))
  (if bad
      (progn
        (princ "\nOASIS: the outline runs through itself --")
        (foreach p bad
          (princ (strcat "\n         the " (car p) " arc crosses the "
                         (cadr p) " arc")))
        (princ "\n       That is not a pool.  One U takes it away; try a")
        (princ "\n       smaller radius on either of the arcs named.")))
  (princ))

;; Say how the finished outline compares with the envelope it was asked
;; to fill.  Everything impossible was refused at the question that
;; caused it, so anything left here is legal but worth knowing about -- a
;; top bulge wide enough to swing out past a side before its tangent arcs
;; catch it, most often.  The arc that is out is named, because the
;; radius behind an overrun is not always the one you would guess.
(defun oasis:report-extents (arcs w h / over p)
  (setq over (oasis:overruns arcs w h))
  (if over
      (progn
        (princ "\nOASIS: the outline does NOT stay inside the envelope --")
        (foreach p over
          (princ (strcat "\n         the " (caddr p) " arc goes "
                         (rtos (cadr p)) " past " (car p))))
        (princ "\n       Drawn as asked; try a smaller radius on the arc")
        (princ "\n       named, and on the bulge either side of it."))
  )
  (princ))

;;; -------------------- the command -------------------------------------

(defun c:OASIS ( / *error* undo-open guard ans pos k steps v var base w h
                   rl rt rr ftl ftr fbc cbase arcs ents nests prev lt a nchk)
  (defun *error* (msg)
    ;; user settings come back FIRST so nothing below can skip them
    (cal:dimstyrestore)
    (cal:sysrestore)
    ;; an Esc part-way through a dimension leaves that command pending,
    ;; and the UNDO below would be swallowed as an answer to it
    (setq guard 0)
    (while (and (> (getvar "CMDACTIVE") 0) (< guard 10))
      (command)
      (setq guard (1+ guard)))
    ;; the preview is scaffolding, not a result -- it goes whether the run
    ;; finished or the user pressed Esc part-way through the questions
    (oasis:pv-clear prev)
    (if undo-open (command "_.UNDO" "_End"))
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nOASIS error: " msg)))
    (princ))

  (cal:syssave '("OSMODE" "CMDECHO" "CLAYER"))
  (cal:dimstysave)

  (cond
    ;; -- a plan pool has nothing sensible to draw in a UCS that is not
    ;;    flat in the world plan, and half of what it draws (the arcs)
    ;;    could not follow it there anyway
    ((not (oasis:ucs-flat-p))
     (princ (strcat "\nOASIS: the current UCS is tilted out of the world"
                    " plan, so a flat plan pool"))
     (princ (strcat "\n       cannot be laid out in it.  Set the UCS back"
                    " to World (or to any"))
     (princ "\n       plan UCS) and run OASIS again.")
     (cal:sysrestore))
    (t

     (setvar "CMDECHO" 0)
     (command "_.UNDO" "_Begin")
     (setq undo-open T)
     (cal:ensure-layer oasis:*poollayer* oasis:*poolcolor*)
     (cal:ensure-layer oasis:*guidelayer* oasis:*guidecolor*)
     (cal:ensure-layer oasis:*dimlayer* oasis:*dimcolor*)

     ;; -- which shape, where it goes, and then the eight measurements,
     ;;    with Back between them all.  Every check reads the answers
     ;;    already given, so backing up to change one re-checks
     ;;    everything that follows it -- and the preview is redrawn
     ;;    before each question, with the circle being asked about
     ;;    picked out in red.
     ;;    Which slots get asked, and in what order, is the shape's own
     ;;    business -- so the step list is re-read every time round,
     ;;    and changing the shape at the first question changes every
     ;;    question after it.
     (setq ans '(nil nil nil nil nil nil nil nil nil nil nil)
           pos 0)
     (while (progn (setq steps (oasis:steps ans))
                   (< pos (length steps)))
       (setq k    (nth pos steps)
             prev (oasis:preview prev ans k)
             v    (oasis:askstep k ans))
       (if (eq v 'CAL-BACK)
           (if (> pos 0)
               (progn (princ "\nStepping back one step.")
                      (setq pos (1- pos)))
               (princ "\nAlready at the first step."))
           (progn
             (setq ans (oasis:put ans k v)
                   pos (1+ pos))
             ;; the right bulge is the last one asked for on every shape,
             ;; so it is where anything the sides do TOGETHER finally
             ;; shows up: a nesting on the oasis shapes, an unreachable
             ;; top circle on the asymmetric kidney
             (if (= k 6)
                 (cond
                   ((= (oasis:variant ans) "AsymKidney")
                    (if (not (oasis:kidney-top (nth 2 ans) (nth 3 ans)
                                               (nth 4 ans) (nth 6 ans)))
                        (progn
                          (princ (strcat "\nNo circle can be tangent to the"
                                         " top of the envelope and touch"
                                         " both those sides from outside"
                                         " them.  Sides more alike (or"
                                         " larger) usually fix it.  Asking"
                                         " again."))
                          (setq pos (1- pos)))))
                   ((not (oasis:kidney-p (oasis:variant ans)))
                    (setq nests (oasis:right-nests (nth 2 ans) (nth 3 ans)
                                                   (nth 4 ans) (nth 5 ans)
                                                   (nth 6 ans)
                                                   (oasis:variant ans)))
                    (if nests
                        (progn
                          (princ (strcat "\nThat right bulge and the " nests
                                         " bulge lie one inside the other, so no"
                                         " tangent radius can join them.  Asking"
                                         " again."))
                          (setq pos (1- pos))))))))))

     (setq prev (oasis:pv-clear prev)
           var  (oasis:variant ans) base (nth 1 ans)
           w    (nth 2 ans) h    (nth 3 ans)
           rl   (oasis:leftrad var (nth 3 ans) (nth 4 ans))
           rt   (nth 5 ans) rr (nth 6 ans)
           ftl  (nth 7 ans) ftr  (nth 8 ans) fbc (nth 9 ans)
           arcs (oasis:solve w h rl rt rr ftl ftr fbc var))

     (if (not arcs)
         (progn
           (princ (strcat "\nOASIS: those radii do not make a closed outline"
                          " -- nothing drawn."))
           (command "_.UNDO" "_End")
           (setq undo-open nil)
           (cal:sysrestore))
         (progn
           (cal:osdown)
           (setq lt    (oasis:dashlt w h)
                 cbase (oasis:checkbase base w h))
           (setvar "CLAYER" oasis:*poollayer*)
           (setq ents (oasis:draw arcs base oasis:*poollayer*))
           (oasis:dimension arcs ents base w h oasis:*dimlayer*)
           (setq nchk (oasis:checkdraw arcs cbase w h lt))
           (cal:dimstyrestore)

           (command "_.UNDO" "_End")
           (setq undo-open nil)
           (cal:sysrestore)

           (princ (strcat "\nOASIS " *oasis-version* ": " (rtos w) " x "
                          (rtos h) " " (oasis:vlabel var)
                          " oasis on layer " oasis:*poollayer* "."))
           (foreach a arcs
             (princ (strcat "\n  " (oasis:pad (nth 0 a) 14)
                            (if (oasis:line-p a)
                                (strcat "flat run, "
                                        (rtos (distance (nth 1 a) (nth 2 a))))
                                (strcat (if (nth 5 a) "bulge  R" "reverse R")
                                        (rtos (nth 2 a))))
                            (cond ((nth 6 a) "")
                                  ((oasis:kidney-p var)
                                   "   (derived from the tangency)")
                                  (t "   (pinned by the envelope)")))))
           (princ (strcat "\n  " (itoa (+ 2 (length arcs)))
                          " dimensions on the pool in the " oasis:*dimstyle*
                          " style, and " (itoa nchk) " on the"))
           (princ (strcat "\n  check drawing beside it in " oasis:*crossstyle*
                          " -- all on layer " oasis:*dimlayer* "."))
           (oasis:report-extents arcs w h)
           (oasis:report-crossings arcs)))))
  (princ))

(defun c:OASISVER ()
  (princ (strcat "\nOASIS " *oasis-version*))
  (princ))

(princ (strcat "\nOASIS " *oasis-version*
               " loaded.  Type OASIS to draw a continuous-tangent pool."))
(princ)
