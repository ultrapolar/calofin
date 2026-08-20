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
;;; one off the top, one off the right -- and between each neighbouring
;;; pair a smaller reverse arc curves back IN, so the outline changes
;;; direction without ever changing tangent.  That is what "continuous
;;; tangent" buys: every joint in the perimeter is smooth, which is why
;;; the whole outline can be given as six radii and two overall
;;; dimensions.
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
;;;   top bulge     touches the Y-max bound, centred across X
;;;                                                     -> centre (X/2, Y-rT)
;;;
;;; So the box's bottom edge is held by the two side bulges together
;;; (each dips to it), the left and right edges by their own bulge, and
;;; the top edge by the top bulge.  Only the top bulge has any freedom
;;; left, and it is spent centring it: oasis:*topfrac* moves it along X
;;; if a job ever needs it off-centre.
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
;;; The six arcs on the POOL layer, and, unless the dimension question
;;; is answered No, the overall X and Y and a radius dimension on each
;;; of the six arcs, on the DIMENSION layer.  The envelope box itself is
;;; construction and is NOT drawn.
;;;
;;; What it refuses
;;; ---------------
;;; Three things make the shape impossible rather than merely ugly, and
;;; each is caught at the question that causes it rather than after all
;;; eight answers are in:
;;;
;;;   * a side bulge taller than the Y bound (2 x radius > Y): it would
;;;     push out through the top edge;
;;;   * one bulge circle wholly inside another: no tangent radius of any
;;;     size can bridge them, because raising it grows both reaches
;;;     equally;
;;;   * a tangent radius too small to span the gap between its two
;;;     bulges -- the routine says the smallest one that will.
;;;
;;; Anything that is merely unusual is drawn and reported, not refused.
;;; Two things are measured on the finished outline and named if they
;;; are wrong: its true extents against the box that was asked for, and
;;; whether it runs through itself -- radii wildly out of proportion can
;;; send one arc clean through another even though all six exist and
;;; close.  Both are drawn anyway, so the problem is on the screen where
;;; it can be seen, and one U takes it away.
;;; ======================================================================

(setq *oasis-version* "v1.0")   ; announced on load; release_lisp.py
                                ; reads this banner and stamps the
                                ; dated twin in releases/ from it

;;; -------------------- tunables ----------------------------------------

(setq oasis:*poollayer* "POOL")       ; the six arcs
(setq oasis:*poolcolor* 4)
(setq oasis:*dimlayer*  "DIMENSION")  ; the dimensions
(setq oasis:*dimcolor*  2)

;; Where the top bulge sits across the X bound, as a fraction of it.
;; 0.5 centres it, which is what every oasis on file wants; the value
;; is here so an off-centre one does not need the file edited twice.
(setq oasis:*topfrac* 0.5)

;; Slack for "is this the same point / the same length" tests, drawing
;; units.  Measurements arrive in inches, so this is far below anything
;; a tape can tell apart.
(setq oasis:*fuzz* 1.0e-6)

;;; -------------------- ask layer ---------------------------------------
;;; Copies of the CALOFIN-LIB helpers under this file's own prefix, so
;;; the standalone build loads alone (STANDARDS.md section 4).  The Back
;;; sentinel is the symbol OASIS-BACK.

;; Keyword question.  kws is the initget string, shown the bracketed
;; list, dflt the Enter answer (nil = an answer is required).  Returns
;; the keyword, or OASIS-BACK for Back/Undo.
(defun oasis:askkw (msg kws shown dflt back / v)
  (initget (if dflt 0 (if back 0 1))
           (if back (strcat kws " Back Undo") kws))
  (setq v (getkword (strcat "\n" msg " [" shown
                            (if back "/Back" "") "]"
                            (if dflt (strcat " <" dflt ">") "") ": ")))
  (cond ((member v '("Back" "Undo")) 'OASIS-BACK)
        ((null v) (if dflt dflt (oasis:askkw msg kws shown dflt back)))
        (t v)))

;; Yes/No that can be backed out of.  Returns T, nil or OASIS-BACK.
(defun oasis:askyn (msg dflt back / v)
  (setq v (oasis:askkw msg "Yes No" "Yes/No" dflt back))
  (if (eq v 'OASIS-BACK) v (= v "Yes")))

;; Distance entry with the kind system of STANDARDS.md section 3:
;; REQ required, NAX/ZER accept NA, SUG offers a default.  Returns the
;; number, nil for NA, or OASIS-BACK.
(defun oasis:askdist (kind msg dflt back / v kw)
  ;; Undo is accepted everywhere Back is, as a hidden synonym
  (setq kw (cond ((eq kind 'REQ) (if back "Back Undo" nil))
                 (back "NA Back Undo")
                 (t "NA")))
  ;; REQ always rejects zero -- offering Back must not loosen what
  ;; counts as a valid measurement; ZER alone admits 0
  (if kw
      (initget (cond ((eq kind 'ZER) 5)
                     ((and (eq kind 'SUG) dflt) 6)
                     (t 7))
               kw)
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
  (cond ((and (= (type v) 'STR) (member v '("Back" "Undo"))) 'OASIS-BACK)
        ((= (type v) 'STR) nil)               ; NA
        ((and (null v) (eq kind 'SUG)) dflt)  ; Enter took the suggestion
        (t v)))

;;; -------------------- layers ------------------------------------------

;; Create the output layer, or - when it already exists - make sure it
;; is on, thawed and unlocked.  Without this a successful run onto a
;; frozen or switched-off layer looks like the command did nothing.
(defun oasis:ensure-layer (name color / rec ed flags col fixed)
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
          (princ (strcat "\nOASIS: layer " name
                         " was off, frozen or locked - restored so the"
                         " result is visible."))))))
  name)

;;; -------------------- geometry ----------------------------------------

;; An angle brought into [0, 2pi).
(defun oasis:angnorm (a)
  (while (< a 0.0) (setq a (+ a pi pi)))
  (while (>= a (+ pi pi)) (setq a (- a pi pi)))
  a)

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
(defun oasis:solve (w h rl rt rr ftl ftr fbc frac
                    / cl ct cr cbc ctr ctl ring n i it c p q s e out)
  (setq cl  (list rl rl)
        ct  (list (* w frac) (- h rt))
        cr  (list (- w rr) rr)
        cbc (oasis:fillet cl rl cr rr fbc)
        ctr (oasis:fillet cr rr ct rt ftr)
        ctl (oasis:fillet ct rt cl rl ftl))
  (if (and cbc ctr ctl)
      (progn
        (setq ring (list (list "left"          cl  rl  T)
                         (list "bottom-center" cbc fbc nil)
                         (list "right"         cr  rr  T)
                         (list "top-right"     ctr ftr nil)
                         (list "top"           ct  rt  T)
                         (list "top-left"      ctl ftl nil))
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

;; Every point the drawn outline can reach: each arc's two ends, plus
;; the compass point of any quadrant its sweep actually crosses.  The
;; bounding box of these is the bounding box of the pool.
(defun oasis:hullpts (arcs / out a c r s w k ang)
  (setq out nil)
  (foreach a arcs
    (setq c   (nth 1 a)
          r   (nth 2 a)
          s   (nth 3 a)
          w   (oasis:angnorm (- (nth 4 a) s))
          out (cons (polar c s r) (cons (polar c (nth 4 a) r) out))
          k   0)
    (while (< k 4)
      (setq ang (* k (/ pi 2.0)))
      (if (<= (oasis:angnorm (- ang s)) w)
          (setq out (cons (polar c ang r) out)))
      (setq k (1+ k))))
  out)

;; (xmin ymin xmax ymax) of a list of points.
(defun oasis:bbox (pts / x0 y0 x1 y1 p)
  (setq x0 (car (car pts))  x1 x0
        y0 (cadr (car pts)) y1 y0)
  (foreach p pts
    (setq x0 (min x0 (car p))  x1 (max x1 (car p))
          y0 (min y0 (cadr p)) y1 (max y1 (cadr p))))
  (list x0 y0 x1 y1))

;; T when the angle ANG falls inside ARC's counter-clockwise sweep.
(defun oasis:on-arc-p (a ang)
  (<= (oasis:angnorm (- ang (nth 3 a)))
      (oasis:angnorm (- (nth 4 a) (nth 3 a)))))

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

;;; -------------------- drawing -----------------------------------------

;; A point in pool coordinates moved to where the pool is being drawn.
(defun oasis:wp (p base)
  (list (+ (car p) (car base))
        (+ (cadr p) (cadr base))
        0.0))

;; The six arcs, drawn in the order they run round the pool.  Returns
;; their entity names in that same order, so the radius dimensions can
;; hook onto them afterwards.
(defun oasis:draw (arcs base lay / out a)
  (setq out nil)
  (foreach a arcs
    (entmake (list '(0 . "ARC")
                   (cons 8 lay)
                   (cons 10 (oasis:wp (nth 1 a) base))
                   (cons 40 (nth 2 a))
                   (cons 50 (nth 3 a))
                   (cons 51 (nth 4 a))))
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
        w (oasis:angnorm (- (nth 4 a) s))
        m (polar c (oasis:angnorm (+ s (/ w 2.0))) r))
  (cons m (if (nth 5 a) (angle c m) (angle m c))))

;; Overall X, overall Y, and a radius on each of the six arcs.  The two
;; overall dimensions are hooked to the points that actually touch the
;; envelope -- the left and right bulges' outermost points for X, the
;; top bulge's highest point and the left bulge's lowest for Y -- so
;; they measure the bounds the user was asked for, not a chord of them.
(defun oasis:dimension (arcs ents base w h rl rr frac lay / doff i e md)
  (setvar "CLAYER" lay)
  (setq doff (oasis:dimoff w h))
  (command "_.DIMLINEAR"
           (oasis:wp (list 0.0 rl) base)
           (oasis:wp (list w rr) base)
           "_H"
           (oasis:wp (list (* 0.5 w) (+ h doff)) base))
  (command "_.DIMLINEAR"
           (oasis:wp (list (* w frac) h) base)
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

;;; -------------------- the questions -----------------------------------

;; lst with slot k replaced by v.  The answer list keeps its length, so
;; a Back and a re-answer overwrite in place instead of growing it.
(defun oasis:put (lst k v / i out e)
  (setq i 0 out nil)
  (foreach e lst
    (setq out (cons (if (= i k) v e) out)
          i   (1+ i)))
  (reverse out))

;; A side bulge's radius, re-asked until it fits inside the Y bound.
;; A bulge is tangent to the bottom edge, so its top sits at twice its
;; radius: any more than half the Y bound and it breaks out of the top.
(defun oasis:ask-bulge (msg side h / v)
  (setq v (oasis:askdist 'REQ msg nil T))
  (while (and (not (eq v 'OASIS-BACK))
              (> (* 2.0 v) (+ h oasis:*fuzz*)))
    (princ (strcat "\nA " (rtos v) " " side " bulge stands "
                   (rtos (* 2.0 v)) " tall and breaks out through the top"
                   " of a " (rtos h) " envelope.  " (rtos (/ h 2.0))
                   " or less."))
    (setq v (oasis:askdist 'REQ msg nil T)))
  v)

;; The top bulge's radius, re-asked while it swallows a side bulge (or
;; is swallowed by one).  Nesting cannot be cured with a tangent radius
;; later, so it has to be caught here.
(defun oasis:ask-top (msg w h rl frac / v cl ct)
  (setq cl (list rl rl)
        v  (oasis:askdist 'REQ msg nil T))
  (while (and (not (eq v 'OASIS-BACK))
              (progn (setq ct (list (* w frac) (- h v)))
                     (oasis:nested-p ct v cl rl)))
    (princ (strcat "\nA " (rtos v) " top bulge and the left bulge lie one"
                   " inside the other, so no tangent radius can join them"
                   " -- raising one raises the other's reach by just as"
                   " much.  Try a top radius nearer the left bulge's "
                   (rtos rl) "."))
    (setq v (oasis:askdist 'REQ msg nil T)))
  v)

;; A tangent radius, re-asked until it is big enough to span its two
;; bulges.  Below the minimum the two circles it would have to touch
;; never meet, and there is no such arc at any position.
(defun oasis:ask-tangent (msg c1 r1 c2 r2 / v mn)
  (setq mn (oasis:filmin c1 r1 c2 r2)
        v  (oasis:askdist 'REQ msg nil T))
  (while (and (not (eq v 'OASIS-BACK))
              (<= v (+ mn oasis:*fuzz*)))
    (princ (strcat "\n" (rtos v) " is too short to reach from one bulge"
                   " to the other -- it has to be more than "
                   (rtos mn) "."))
    (setq v (oasis:askdist 'REQ msg nil T)))
  v)

;; One question of the run.  k is its number, ans the answers gathered
;; so far -- the checks that need an earlier answer read it from there,
;; so backing up and changing one re-checks everything after it.
;; Returns the answer, or OASIS-BACK.
(defun oasis:askstep (k ans / w h rl rt rr cl ct cr)
  (setq w  (nth 0 ans) h  (nth 1 ans)
        rl (nth 2 ans) rt (nth 3 ans) rr (nth 4 ans)
        cl (if (and w h rl) (list rl rl))
        ct (if (and w h rt) (list (* w oasis:*topfrac*) (- h rt)))
        cr (if (and w h rr) (list (- w rr) rr)))
  (cond
    ((= k 0) (oasis:askdist 'REQ "X - overall left-to-right bounds" nil nil))
    ((= k 1) (oasis:askdist 'REQ "Y - overall front-to-back bounds" nil T))
    ((= k 2) (oasis:ask-bulge "Left bulge radius" "left" h))
    ((= k 3) (oasis:ask-top "Top bulge radius" w h rl oasis:*topfrac*))
    ((= k 4) (oasis:ask-bulge "Right bulge radius" "right" h))
    ((= k 5) (oasis:ask-tangent "Top-left tangent radius" ct rt cl rl))
    ((= k 6) (oasis:ask-tangent "Top-right tangent radius" cr rr ct rt))
    ((= k 7) (oasis:ask-tangent "Bottom-center tangent radius" cl rl cr rr))
    ((= k 8) (oasis:askyn "Dimension the pool?" "Yes" T))))

;; The right bulge is the last of the three, so it is the one that has
;; to be checked against BOTH of the others before the tangent radii are
;; asked for.  Returns the name of the bulge it nests with, or nil.
(defun oasis:right-nests (w h rl rt rr frac / cl ct cr)
  (setq cl (list rl rl)
        ct (list (* w frac) (- h rt))
        cr (list (- w rr) rr))
  (cond ((oasis:nested-p cr rr cl rl) "left")
        ((oasis:nested-p cr rr ct rt) "top")))

;;; -------------------- reporting ---------------------------------------

;; Say how the finished outline compares with the envelope it was asked
;; to fill.  Everything impossible was refused at the question that
;; caused it, so anything left here is legal but worth knowing about --
;; a top bulge wide enough to swing out past the sides, most often.
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

(defun oasis:report-extents (arcs w h / bb over s)
  (setq bb   (oasis:bbox (oasis:hullpts arcs))
        over nil)
  (if (< (car bb)   (- 0.0 oasis:*fuzz*))
      (setq over (cons (strcat (rtos (abs (car bb))) " past the left") over)))
  (if (< (cadr bb)  (- 0.0 oasis:*fuzz*))
      (setq over (cons (strcat (rtos (abs (cadr bb))) " past the bottom") over)))
  (if (> (caddr bb) (+ w oasis:*fuzz*))
      (setq over (cons (strcat (rtos (- (caddr bb) w)) " past the right") over)))
  (if (> (cadddr bb) (+ h oasis:*fuzz*))
      (setq over (cons (strcat (rtos (- (cadddr bb) h)) " past the top") over)))
  (if over
      (progn
        (princ "\nOASIS: the outline does NOT stay inside the envelope --")
        (foreach s (reverse over) (princ (strcat "\n         " s)))
        (princ (strcat "\n       Drawn as asked; a smaller top bulge (under "
                       (rtos (/ w 2.0)) ") keeps it in."))))
  (princ))

;;; -------------------- the command -------------------------------------

(defun oasis:syssave ()
  (if (not oasis:*sysold*)
    (setq oasis:*sysold*
          (mapcar '(lambda (v) (cons v (getvar v)))
                  '("OSMODE" "CMDECHO" "CLAYER")))))

(defun oasis:sysrestore ( / v p)
  ;; OSMODE first -- object snaps are the setting the user misses most
  ;; if a run is ever cut short partway
  (foreach v '("OSMODE" "CMDECHO" "CLAYER")
    (setq p (assoc v oasis:*sysold*))
    (if p (setvar v (cdr p))))
  (setq oasis:*sysold* nil))

(setq oasis:*sysold* nil)

(defun c:OASIS ( / *error* undo-open guard ans i v w h rl rt rr ftl ftr fbc
                   dims base arcs ents nests)
  (defun *error* (msg)
    ;; user settings come back FIRST so nothing below can skip them
    (oasis:sysrestore)
    ;; an Esc part-way through a dimension leaves that command pending,
    ;; and the UNDO below would be swallowed as an answer to it
    (setq guard 0)
    (while (and (> (getvar "CMDACTIVE") 0) (< guard 10))
      (command)
      (setq guard (1+ guard)))
    (if undo-open (command "_.UNDO" "_End"))
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nOASIS error: " msg)))
    (princ))

  (oasis:syssave)

  ;; -- the eight measurements and the dimension question, with Back
  ;;    between them.  Every check reads the answers already given, so
  ;;    backing up to change one re-checks everything that follows it.
  (setq ans '(nil nil nil nil nil nil nil nil nil)
        i   0)
  (while (< i 9)
    (setq v (oasis:askstep i ans))
    (if (eq v 'OASIS-BACK)
        (if (> i 0)
            (progn (princ "\nStepping back one step.")
                   (setq i (1- i)))
            (princ "\nAlready at the first step."))
        (progn
          (setq ans (oasis:put ans i v)
                i   (1+ i))
          ;; the right bulge is the last of the three, so it is where a
          ;; nesting with EITHER of the others finally shows up
          (if (= i 5)
              (progn
                (setq nests (oasis:right-nests (nth 0 ans) (nth 1 ans)
                                               (nth 2 ans) (nth 3 ans)
                                               (nth 4 ans) oasis:*topfrac*))
                (if nests
                    (progn
                      (princ (strcat "\nThat right bulge and the " nests
                                     " bulge lie one inside the other, so no"
                                     " tangent radius can join them.  Asking"
                                     " again."))
                      (setq i 4))))))))

  (setq w    (nth 0 ans) h   (nth 1 ans)
        rl   (nth 2 ans) rt  (nth 3 ans) rr (nth 4 ans)
        ftl  (nth 5 ans) ftr (nth 6 ans) fbc (nth 7 ans)
        dims (nth 8 ans)
        arcs (oasis:solve w h rl rt rr ftl ftr fbc oasis:*topfrac*))

  (if (not arcs)
      (progn
        (princ (strcat "\nOASIS: those radii do not make a closed outline"
                       " -- nothing drawn."))
        (oasis:sysrestore))
      (progn
        ;; the base point is picked with the user's own snaps still
        ;; live; only afterwards do snaps drop for the drawing work
        (setq base (getpoint "\nInsertion base point <0,0>: ")
              base (if base (list (car base) (cadr base)) (list 0.0 0.0)))
        (setvar "CMDECHO" 0)
        (setvar "OSMODE" 0)
        (command "_.UNDO" "_Begin")
        (setq undo-open T)

        (oasis:ensure-layer oasis:*poollayer* oasis:*poolcolor*)
        (setq ents (oasis:draw arcs base oasis:*poollayer*))
        (if dims
            (progn
              (oasis:ensure-layer oasis:*dimlayer* oasis:*dimcolor*)
              (oasis:dimension arcs ents base w h rl rr oasis:*topfrac*
                               oasis:*dimlayer*)))

        (command "_.UNDO" "_End")
        (setq undo-open nil)
        (oasis:sysrestore)

        (princ (strcat "\nOASIS " *oasis-version* ": " (rtos w) " x "
                       (rtos h) " continuous-tangent pool on layer "
                       oasis:*poollayer* "."))
        (princ (strcat "\n  Bulges: " (rtos rl) " left, " (rtos rt)
                       " top, " (rtos rr) " right."))
        (princ (strcat "\n  Tangent radii: " (rtos ftl) " top-left, "
                       (rtos ftr) " top-right, " (rtos fbc)
                       " bottom-center."))
        (if dims
            (princ (strcat "\n  8 dimensions on layer " oasis:*dimlayer*
                           " (overall X and Y, and a radius on each arc).")))
        (oasis:report-extents arcs w h)
        (oasis:report-crossings arcs)))
  (princ))

(defun c:OASISVER ()
  (princ (strcat "\nOASIS " *oasis-version*))
  (princ))

(princ (strcat "\nOASIS " *oasis-version*
               " loaded.  Type OASIS to draw a continuous-tangent pool."))
(princ)
