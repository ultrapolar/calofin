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
;;; An oasis pool is six arcs and nothing else: no straight runs, no
;;; corners.  Three of them bulge OUT -- one off the left of the pool,
;;; one off the right, one off the top -- and between each neighbouring
;;; pair a smaller reverse arc curves back IN, so the outline changes
;;; direction without ever changing tangent.  That is what "continuous
;;; tangent" buys: every joint in the perimeter is smooth, which is why
;;; the whole outline can be given as six radii and two overall
;;; dimensions.
;;;
;;; They come two ways, and the first question is which:
;;;
;;;   CENTER BULGE      the third bulge sits across the top, centred.
;;;   TOP RIGHT BULGE   it is tucked into the top-right corner instead.
;;;
;;; That is the ONLY difference.  Same six arcs, same ring, same solver,
;;; same checks -- only where the third bulge's centre lands, and the
;;; names the arcs go by because of it.
;;;
;;;                        top bulge
;;;                      ___________
;;;          top-left  ,'           `.  top-right
;;;          tangent  /               \  tangent
;;;                  |                 |
;;;      left bulge  |                 |  right bulge
;;;                   \      ___      /
;;;                    `.__,'   `.__,'
;;;                     bottom-center tangent
;;;
;;; Where the circles sit
;;; ---------------------
;;; The X and Y the user gives are ABSOLUTE bounds -- the pool touches
;;; all four of them and crosses none.  That pins the three bulges with
;;; no further input:
;;;
;;;   left bulge    touches the X-min and Y-min bounds  -> centre (rL, rL)
;;;   right bulge   touches the X-max and Y-min bounds  -> centre (X-rR, rR)
;;;   top bulge     CENTER    touches the Y-max bound, centred across X
;;;                                                     -> centre (X/2, Y-rT)
;;;                 TOPRIGHT  touches the Y-max AND the X-max bound
;;;                                                     -> centre (X-rT, Y-rT)
;;;
;;; So the box's bottom edge is held by the two side bulges together
;;; (each dips to it), the left edge by the left bulge, the top edge by
;;; the top bulge -- and the right edge by the right bulge alone on a
;;; centre-bulge pool, or by the right bulge AND the corner bulge, with
;;; a reverse curve between them, on a top-right one.  On a centre-bulge
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
;;;     of neighbouring centres tied to each other.  Eighteen dimensions
;;;     that between them pin all six centres against the box and against
;;;     one another, so a transcription slip in any single radius shows
;;;     up as a dimension that does not agree with the order sheet.  The
;;;     centre-to-centre ties have a second use: neighbouring circles are
;;;     externally tangent by construction, so each of those must read
;;;     exactly the two radii added together.
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

(setq *oasis-version* "v3.0")   ; announced on load; release_lisp.py
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

;;; -------------------- the two shapes -----------------------------------
;;; An oasis comes two ways, and they differ in exactly ONE thing: where
;;; the third bulge sits.  Everything else -- the other two bulges, the
;;; three tangent circles between them, the ring they run in, the whole
;;; solver -- is the same for both.
;;;
;;;   Center    the third bulge is tangent to the Y-max bound and centred
;;;             across X.  The common one.
;;;   TopRight  it is tucked into the corner instead, tangent to the Y-max
;;;             AND the X-max bound, so the right-hand side of the pool
;;;             touches its bound twice with a reverse curve between.
;;;
;;; The names the arcs go by change with it, because "top-right" means the
;;; tangent arc on one and the bulge itself on the other.

;; Where the third bulge sits -- the one thing the two shapes differ in.
(defun oasis:topcen (w h rt variant)
  (if (= variant "TopRight")
      (list (- w rt) (- h rt))
      (list (* w oasis:*topfrac*) (- h rt))))

;; What the six arcs are called, in the order they run round the pool.
(defun oasis:names (variant)
  (if (= variant "TopRight")
      '("left" "bottom-center" "right" "right-side" "top-right" "top-left")
      '("left" "bottom-center" "right" "top-right" "top" "top-left")))

;; What each of the six radius questions is called.  k is 0-5 in the order
;; they are asked: the three bulges, then the three tangents.
(defun oasis:rprompt (variant k)
  (nth k (if (= variant "TopRight")
             '("Left bulge radius" "Top-right bulge radius"
               "Right bulge radius" "Top-left tangent radius"
               "Right-side tangent radius" "Bottom-center tangent radius")
             '("Left bulge radius" "Top bulge radius"
               "Right bulge radius" "Top-left tangent radius"
               "Top-right tangent radius" "Bottom-center tangent radius"))))

;; How the shape is named on the command line and in the report.
(defun oasis:vlabel (variant)
  (if (= variant "TopRight") "top-right-bulge" "center-bulge"))

;; T when the third bulge has to fit the envelope the way a side bulge
;; does.  The corner one is tangent to two bounds, so it is twice its
;; radius both ways and can break out of either; the centred one is
;; trimmed away long before it reaches anything.
(defun oasis:topfits-p (variant) (= variant "TopRight"))

;; Where the top bulge sits across the X bound, as a fraction of it.
;; 0.5 centres it, which is what every oasis on file wants; the value
;; is here so an off-centre one does not need the file edited twice.
(setq oasis:*topfrac* 0.5)

;; Slack for "is this the same point / the same length" tests, drawing
;; units.  Measurements arrive in inches, so this is far below anything
;; a tape can tell apart.
(setq oasis:*fuzz* 1.0e-6)

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

;; Centre of the circle of radius rf externally tangent to both (c1 r1)
;; and (c2 r2) and lying on the RIGHT of c1->c2.  The bulges are named
;; counter-clockwise round the pool, and a counter-clockwise ring keeps
;; the water on its left, so the right-hand solution is the one outside
;; the pool -- the one whose near side becomes the reverse curve.
(defun oasis:fillet (c1 r1 c2 r2 rf)
  (oasis:circint c1 (+ r1 rf) c2 (+ r2 rf) -1.0))

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

;; The six arcs, in the counter-clockwise order they run round the pool.
;; Each comes back as (name centre radius start-angle end-angle bulge-p)
;; with the angles in RADIANS, counter-clockwise start to end, ready for
;; an ARC entity's group 50 / 51.  nil when a tangent circle does not
;; exist -- c:OASIS checks for that before it ever gets here, so a nil
;; return means an input slipped past the checks, not a user mistake.
(defun oasis:solve (w h rl rt rr ftl ftr fbc variant
                    / cl ct cr cbc ctr ctl ring nm n i it c p q s e out)
  (setq cl  (list rl rl)
        ct  (oasis:topcen w h rt variant)
        cr  (list (- w rr) rr)
        cbc (oasis:fillet cl rl cr rr fbc)
        ctr (oasis:fillet cr rr ct rt ftr)
        ctl (oasis:fillet ct rt cl rl ftl))
  (if (and cbc ctr ctl)
      (progn
        (setq nm   (oasis:names variant)
              ring (list (list (nth 0 nm) cl  rl  T)
                         (list (nth 1 nm) cbc fbc nil)
                         (list (nth 2 nm) cr  rr  T)
                         (list (nth 3 nm) ctr ftr nil)
                         (list (nth 4 nm) ct  rt  T)
                         (list (nth 5 nm) ctl ftl nil))
              n    (length ring)
              i    0
              out  nil)
        (while (< i n)
          (setq it (nth i ring)
                c  (nth 1 it)
                p  (nth 1 (nth (rem (+ i n -1) n) ring))   ; neighbour before
                q  (nth 1 (nth (rem (+ i 1) n) ring)))     ; neighbour after
          ;; a bulge runs with the walk, from the tangent point it
          ;; shares with the arc before it to the one it shares with the
          ;; arc after; a reverse arc curves the other way, so on its
          ;; own circle those two ends swap over
          (if (nth 3 it)
              (setq s (angle c p) e (angle c q))
              (setq s (angle c q) e (angle c p)))
          (setq out (cons (list (nth 0 it) c (nth 2 it) s e (nth 3 it)) out)
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
          sw (cal:angnorm (- (nth 4 a) s))
          k  -2)
    (while (< k 4)
      (setq ang (cond ((= k -2) s)
                      ((= k -1) (nth 4 a))
                      (t (* k (/ pi 2.0)))))
      (if (or (minusp k) (<= (cal:angnorm (- ang s)) sw))
          (setq p    (polar c ang r)
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
;; BOTH sweeps -- nine pairs, eighteen points, and no curve to walk.
(defun oasis:crossings (arcs / n i j a b p side pair out)
  (setq n (length arcs) i 0 out nil)
  (while (< i n)
    (setq j (1+ i))
    (while (< j n)
      (if (not (or (= j (1+ i)) (and (= i 0) (= j (1- n)))))
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
    (entmake (list '(0 . "ARC")
                   (cons 8 lay)
                   (cons 10 (trans (oasis:wp (nth 1 a) base) 1 0))
                   (cons 40 (nth 2 a))
                   (cons 50 (cal:angnorm (+ (nth 3 a) rot)))
                   (cons 51 (cal:angnorm (+ (nth 4 a) rot)))))
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
  (setq c (nth 1 a)
        r (nth 2 a)
        s (nth 3 a)
        w (cal:angnorm (- (nth 4 a) s))
        m (polar c (cal:angnorm (+ s (/ w 2.0))) r))
  (cons m (if (nth 5 a) (angle c m) (angle m c))))

;; Overall X, overall Y, and a radius on each of the six arcs.  The two
;; overall dimensions are hooked to the points that actually touch the
;; envelope -- the left and right bulges' outermost points for X, the
;; top bulge's highest point and the left bulge's lowest for Y -- so
;; they measure the bounds the user was asked for, not a chord of them.
(defun oasis:dimension (arcs ents base w h rl rr lay / doff i e md)
  (setvar "CLAYER" lay)
  (oasis:dimstyle-on oasis:*dimstyle*)
  (setq doff (oasis:dimoff w h))
  (command "_.DIMLINEAR"
           (oasis:wp (list 0.0 rl) base)
           (oasis:wp (list w rr) base)
           "_H"
           (oasis:wp (list (* 0.5 w) (+ h doff)) base))
  ;; the top bulge's own highest point, wherever that bulge sits
  (command "_.DIMLINEAR"
           (oasis:wp (list (car (nth 1 (nth 4 arcs))) h) base)
           (oasis:wp (list rl 0.0) base)
           "_V"
           (oasis:wp (list (- 0.0 doff) (* 0.5 h)) base))
  ;; walked by index so each arc keeps the entity oasis:draw made for it
  (setq i 0)
  (while (< i (length arcs))
    (setq e  (nth i ents)
          md (oasis:arcmid (nth i arcs))
          i  (1+ i))
    (if e
        (command "_.DIMRADIUS"
                 (list e (oasis:wp (car md) base))
                 (oasis:wp (polar (car md) (cdr md) (* 0.9 doff)) base))))
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
(defun oasis:checkdraw (arcs cbase w h lt / mark i a c near)
  (oasis:dimstyle-on oasis:*crossstyle*)
  (setvar "CLAYER" oasis:*guidelayer*)
  (oasis:pv-box w h cbase lt)
  (setq mark (max 1.0 (/ (max w h) 90.0))
        i    0)
  ;; the outline itself, so the centres have something to belong to
  (oasis:draw arcs cbase oasis:*poollayer*)
  (setvar "CLAYER" oasis:*guidelayer*)
  (while (< i 6)
    (oasis:pv-circle (nth 1 (nth i arcs)) mark cbase "CONTINUOUS" nil)
    (setq i (1+ i)))
  (setvar "CLAYER" oasis:*dimlayer*)
  ;; every centre back to the two corners nearest it
  (setq i 0)
  (while (< i 6)
    (setq a    (nth i arcs)
          c    (nth 1 a)
          near (oasis:near2 c w h)
          i    (1+ i))
    (oasis:crossdim c (car near) cbase)
    (oasis:crossdim c (cadr near) cbase))
  ;; and every centre to the one next round the ring -- each of these
  ;; must read the two radii added together, because the circles are
  ;; externally tangent
  (setq i 0)
  (while (< i 6)
    (oasis:crossdim (nth 1 (nth i arcs))
                    (nth 1 (nth (rem (1+ i) 6) arcs))
                    cbase)
    (setq i (1+ i)))
  (princ))

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
(defun oasis:fillin (ans / var w h rl rt rr cl ct cr side top g)
  (setq var  (nth 0 ans)
        w    (nth 2 ans)
        h    (nth 3 ans)
        side (* 0.5 oasis:*startside* (min w h))
        ;; the centred bulge is measured across the long bound, the
        ;; corner one across the short -- it has to fit both ways
        top  (* 0.5 oasis:*starttop*
                (if (oasis:topfits-p var) (min w h) w))
        rl   (cond ((nth 4 ans)) (side))
        rt   (cond ((nth 5 ans)) (top))
        rr   (cond ((nth 6 ans)) (side))
        ;; a tangent circle is read against the bulges either side of it,
        ;; not against the envelope, so size it off the smallest bulge --
        ;; that keeps the bulges the bigger circles, which is the whole
        ;; point of the starting picture
        g    (* 0.6 (min rl rt rr))
        cl   (list rl rl)
        ct   (oasis:topcen w h rt var)
        cr   (list (- w rr) rr))
  (list w h rl rt rr
        (cond ((nth 7 ans)) ((max g (* 1.25 (oasis:filmin ct rt cl rl)))))
        (cond ((nth 8 ans)) ((max g (* 1.25 (oasis:filmin cr rr ct rt)))))
        (cond ((nth 9 ans)) ((max g (* 1.25 (oasis:filmin cl rl cr rr)))))))

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

;; Which of the six ring positions each question is about, so the right
;; circle goes red: 0 left, 1 bottom-center, 2 right, 3 top-right,
;; 4 top, 5 top-left.  The two bounds questions are about no circle.
(defun oasis:qring (k)
  (cond ((= k 4) 0) ((= k 5) 4) ((= k 6) 2)
        ((= k 7) 5) ((= k 8) 3) ((= k 9) 1)))

;; The envelope box, dashed -- the bounds the pool is being fitted to.
(defun oasis:pv-box (w h base lt / out)
  (setq out (list (oasis:pv-line (list 0.0 0.0) (list w 0.0) base lt)
                  (oasis:pv-line (list w 0.0) (list w h) base lt)
                  (oasis:pv-line (list w h) (list 0.0 h) base lt)
                  (oasis:pv-line (list 0.0 h) (list 0.0 0.0) base lt)))
  out)

;; Redraw the preview for question K and hand back the entities it made,
;; ready to be passed to the next call so they can be cleared first.
;; Nothing is drawn until both bounds are known -- before that there is
;; no envelope to draw anything inside.
(defun oasis:preview (old ans k
                      / var base w h full arcs lt out hi ring i a md txt
                        hgt slot)
  (oasis:pv-clear old)
  (setq var  (nth 0 ans)
        base (nth 1 ans)
        w    (nth 2 ans)
        h    (nth 3 ans)
        out  nil)
  (if (and base w h)
      (progn
        (cal:osdown)
        (setq lt   (oasis:dashlt w h)
              hgt  (/ (max w h) 28.0)
              hi   (oasis:qring k)
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
                    i    0)
              (if hi (oasis:recolor (nth hi ring) oasis:*hicolor*))
              (while (< i 6)
                (setq a    (nth i arcs)
                      md   (oasis:arcmid a)
                      slot (oasis:qslot i)
                      txt  (if (nth slot ans) (rtos (nth slot ans)) "?")
                      out  (cons (oasis:pv-circle (nth 1 a) (nth 2 a) base lt
                                                  (and hi (= i hi)))
                                 out)
                      out  (cons (oasis:pv-text
                                   (polar (car md) (cdr md) (* 1.7 hgt))
                                   hgt txt base (and hi (= i hi)))
                                 out)
                      i    (1+ i)))))
        (cal:osup)))
  out)

;; Which answer slot holds ring position I's radius -- the inverse of
;; oasis:qring.
(defun oasis:qslot (i)
  (cond ((= i 0) 4) ((= i 1) 9) ((= i 2) 6)
        ((= i 3) 8) ((= i 4) 5) (t 7)))

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

;; One question of the run.  k is its number, ans the answers gathered so
;; far -- the checks that need an earlier answer read it from there, so
;; backing up and changing one re-checks everything after it.  Returns
;; the answer, or OASIS-BACK.
;;
;;   0 which shape       3 Y bound      6 right bulge    9 bottom-center
;;   1 base point        4 left bulge   7 top-left tangent
;;   2 X bound           5 top bulge    8 top-right / right-side tangent
(defun oasis:askstep (k ans / var w h rl rt rr cl ct cr)
  (setq var (nth 0 ans)
        w   (nth 2 ans) h  (nth 3 ans)
        rl  (nth 4 ans) rt (nth 5 ans) rr (nth 6 ans)
        cl  (if (and w h rl) (list rl rl))
        ct  (if (and w h rt) (oasis:topcen w h rt var))
        cr  (if (and w h rr) (list (- w rr) rr)))
  (cond
    ((= k 0) (cal:askkw "Where is the top bulge?"
                          "Center TopRight" "Center/TopRight" "Center" nil))
    ((= k 1) (oasis:askbase T))
    ((= k 2) (cal:askdist 'REQ "X - overall left-to-right bounds" nil T))
    ((= k 3) (cal:askdist 'REQ "Y - overall front-to-back bounds" nil T))
    ((= k 4) (oasis:ask-bulge (oasis:rprompt var 0) "left" w h))
    ((= k 5) (oasis:ask-top (oasis:rprompt var 1) w h rl var))
    ((= k 6) (oasis:ask-bulge (oasis:rprompt var 2) "right" w h))
    ((= k 7) (oasis:ask-tangent (oasis:rprompt var 3) ct rt cl rl))
    ((= k 8) (oasis:ask-tangent (oasis:rprompt var 4) cr rr ct rt))
    ((= k 9) (oasis:ask-tangent (oasis:rprompt var 5) cl rl cr rr))))

;; The right bulge is the last of the three, so it is the one that has
;; to be checked against BOTH of the others before the tangent radii are
;; asked for.  Returns the name of the bulge it nests with, or nil.
(defun oasis:right-nests (w h rl rt rr variant / cl ct cr)
  (setq cl (list rl rl)
        ct (oasis:topcen w h rt variant)
        cr (list (- w rr) rr))
  (cond ((oasis:nested-p cr rr cl rl) "left")
        ((oasis:nested-p cr rr ct rt) "top")))

;;; -------------------- reporting ---------------------------------------

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

(defun c:OASIS ( / *error* undo-open guard ans i v var base w h rl rt rr
                   ftl ftr fbc cbase arcs ents nests prev lt)
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
     (setq ans '(nil nil nil nil nil nil nil nil nil nil)
           i   0)
     (while (< i 10)
       (setq prev (oasis:preview prev ans i)
             v    (oasis:askstep i ans))
       (if (eq v 'CAL-BACK)
           (if (> i 0)
               (progn (princ "\nStepping back one step.")
                      (setq i (1- i)))
               (princ "\nAlready at the first step."))
           (progn
             (setq ans (oasis:put ans i v)
                   i   (1+ i))
             ;; the right bulge is the last of the three, so it is where a
             ;; nesting with EITHER of the others finally shows up
             (if (= i 7)
                 (progn
                   (setq nests (oasis:right-nests (nth 2 ans) (nth 3 ans)
                                                  (nth 4 ans) (nth 5 ans)
                                                  (nth 6 ans) (nth 0 ans)))
                   (if nests
                       (progn
                         (princ (strcat "\nThat right bulge and the " nests
                                        " bulge lie one inside the other, so no"
                                        " tangent radius can join them.  Asking"
                                        " again."))
                         (setq i 6))))))))

     (setq prev (oasis:pv-clear prev)
           var  (nth 0 ans) base (nth 1 ans)
           w    (nth 2 ans) h    (nth 3 ans)
           rl   (nth 4 ans) rt   (nth 5 ans) rr (nth 6 ans)
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
           (oasis:dimension arcs ents base w h rl rr oasis:*dimlayer*)
           (oasis:checkdraw arcs cbase w h lt)
           (cal:dimstyrestore)

           (command "_.UNDO" "_End")
           (setq undo-open nil)
           (cal:sysrestore)

           (princ (strcat "\nOASIS " *oasis-version* ": " (rtos w) " x "
                          (rtos h) " " (oasis:vlabel var)
                          " oasis on layer " oasis:*poollayer* "."))
           (princ (strcat "\n  Bulges: " (rtos rl) " left, " (rtos rt) " "
                          (nth 4 (oasis:names var)) ", " (rtos rr) " right."))
           (princ (strcat "\n  Tangent radii: " (rtos ftl) " "
                          (nth 5 (oasis:names var)) ", " (rtos ftr) " "
                          (nth 3 (oasis:names var)) ", " (rtos fbc) " "
                          (nth 1 (oasis:names var)) "."))
           (princ (strcat "\n  8 dimensions on the pool in the "
                          oasis:*dimstyle* " style, and 18 on the check"))
           (princ (strcat "\n  drawing beside it in " oasis:*crossstyle*
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
