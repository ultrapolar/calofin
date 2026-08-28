;;; ======================================================================
;;; OASIS.lsp  --  continuous-tangent pool inside a given X/Y envelope
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  OASIS       draw a continuous-tangent pool
;;;            OASISVER    print the loaded version
;;; ======================================================================
;;;
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
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

(setq *oasis-version* "v8.1")   ; announced on load; release_lisp.py
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

;; The pool bottom.  The offset the hopper question offers first, the
;; number of chords a guided slope line is drawn with, and how finely the
;; deepest point of the offset ring is looked for.
(setq oasis:*hopoff*   18.0)
(setq oasis:*hopchord* 24)
(setq oasis:*hopscan*  720)

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

;; T for the NXT cloud -- three lobes and four fillets, and the one
;; shape whose ring meets a bulge twice.
(defun oasis:nxt-p (variant)
  (= variant "NXTcloud"))

;; T when the run is a COMPLEX one.  Complex is not a shape: it is a
;; second question asked straight after the shape, and what it changes is
;; how much of the outline the user is allowed to say.  A simple run is
;; the shape as it has always been -- bulges pinned to the envelope,
;; reverse arcs between them.  A complex one adds two things a real
;; drawing sometimes has and the simple flow cannot express:
;;
;;   * any joiner may be answered LINE instead of a radius, and comes out
;;     as the straight run between the two bulges' tangent points --
;;     exactly the reverse arc with an infinite radius, so the outline
;;     stays tangent-continuous through it;
;;   * a Center pool's top bulge may be moved off centre by a signed
;;     offset, left negative.
;;
;; Neither changes the ring downstream: a straight joiner is the "LINE"
;; element the cloud's flat bottom already uses, and an offset hump is
;; the same bulge at a different X.
(defun oasis:complex-p (ans)
  (= (nth 11 ans) "Complex"))

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

;; Where the third bulge sits, on the shapes that have one.  off is the
;; complex run's signed shift of a Center pool's hump along X -- negative
;; to the left, nil or zero for the centred one every simple run draws.
;; A corner bulge has no such freedom: two bounds already hold it.
(defun oasis:topcen (w h rt variant off)
  (if (= variant "TopRight")
      (list (- w rt) (- h rt))
      (list (+ (* w oasis:*topfrac*) (cond (off) (0.0))) (- h rt))))

;; Where a NXT cloud's three lobes sit.  All three are pinned by the
;; envelope alone, with nothing left to ask but their radii: the TOP-LEFT
;; one into the corner where the X-min and Y-max walls meet, the CENTRE
;; one on the Y-min wall halfway across, and the RIGHT one on the X-max
;; wall halfway up.
(defun oasis:nxtcen (w h r which)
  (cond ((= which 0) (list r (- h r)))
        ((= which 1) (list (* 0.5 w) r))
        (t           (list (- w r) (* 0.5 h)))))

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
        ;; eight, because the ring meets the centre lobe twice -- once
        ;; under it on the way out to the right, once over it on the way
        ;; back
        ((oasis:nxt-p variant)
         '("top-left" "left-bottom" "center-bottom" "right-bottom"
           "right" "right-top" "center-top" "left-top"))
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
    ((oasis:nxt-p variant)
      (cond ((= slot 4)  "Top-left lobe radius")
            ((= slot 5)  "Center lobe radius")
            ((= slot 6)  "Right lobe radius")
            ((= slot 9)  "Left-bottom tangent radius")
            ((= slot 13) "Right-bottom tangent radius")
            ((= slot 8)  "Right-top tangent radius")
            ((= slot 7)  "Left-top tangent radius")))
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
            ((= slot 9) "Bottom-center tangent radius")
            ((= slot 12) "Top bulge off center, left negative")))))

;; Which answer slots this shape asks for, in the order it asks them.
;; The rest are either pinned by the envelope (a cloud's left bulge) or
;; are no part of the shape at all.
;;
;; The head is the same for every run: the shape, the sub-type on the two
;; families that have one, then simple-or-complex.  Complex adds one
;; question and only to the Center shape -- how far its hump is off
;; centre; the straight runs it also allows are not questions of their
;; own but answers to the joiner questions already being asked.
(defun oasis:steps (ans / fam out)
  (setq fam (nth 0 ans)
        out (cond ((= fam "Cloud")
                   (if (= (nth 10 ans) "Rounded") '(1 2 3 6 7 9)
                       '(1 2 3 6 7)))
                  ((= fam "Kidney")
                   (if (= (nth 10 ans) "Asymmetric") '(1 2 3 4 6 9)
                       '(1 2 3 5 9)))
                  ;; the three lobes, then the four fillets in the order
                  ;; the outline meets them
                  ((= fam "NXTcloud") '(1 2 3 4 5 6 9 13 8 7))
                  ((and (= fam "Center") (oasis:complex-p ans))
                   '(1 2 3 4 5 12 6 7 8 9))
                  (t '(1 2 3 4 5 6 7 8 9))))
  (append (if (member fam '("Cloud" "Kidney")) '(0 10 11) '(0 11)) out))

;; How the shape is named on the command line and in the report.
(defun oasis:vlabel (variant)
  (cond ((= variant "TopRight")       "top-right-bulge")
        ((= variant "StraightBottom") "straight-bottom cloud")
        ((= variant "RoundedBottom")  "rounded-bottom cloud")
        ((= variant "NXTcloud")       "NXT cloud")
        ((= variant "TrueKidney")     "true kidney")
        ((= variant "AsymKidney")     "asymmetric kidney")
        (t                            "center-bulge")))

;; T when the shape's third bulge has to fit the envelope the way a side
;; bulge does.  The corner one is tangent to two bounds, so it is twice
;; its radius both ways and can break out of either; the centred one is
;; trimmed away long before it reaches anything.
(defun oasis:topfits-p (variant) (= variant "TopRight"))

;;; -------------------- form answers -------------------------------------
;;;
;;;  A form -- the LAZFORM oasis sheets, or anything else that can build
;;;  the alist -- can answer some or all of OASIS's questions before the
;;;  run starts.  It leaves them in oasis:*form* as (key . value) and the
;;;  ask helpers below look there first, so a filled-in sheet drives the
;;;  whole run and a half-filled one simply shortens it.  Same contract
;;;  POOL and SPA carry:
;;;
;;;    key absent      the form did not answer it   -> ask, as usual
;;;    (key . 480.0)   the form answered it         -> 480.0, no prompt
;;;
;;;  ONE SLOT PER QUESTION, named after the answer it fills:
;;;
;;;    shape   which family        rl / rt / rr   the three bulges
;;;    sub     a cloud's bottom,   ftl / ftr      the top joiners
;;;            a kidney's type     fbc / fbr      the bottom joiners
;;;    detail  simple or complex   off            a hump off centre
;;;    x / y   the envelope
;;;
;;;  The base point is not among them, and neither is the pool-bottom
;;;  gate at the end: both are picked in the drawing, which is where a
;;;  form has nothing to say.
;;;
;;;  AN ANSWER IS REMOVED AS IT IS USED.  Not marked used -- removed.
;;;  Two things depend on it.  Back would otherwise deadlock: step back
;;;  onto a form-answered question, it answers itself instantly and walks
;;;  forward again, and there is no key the user can press to get out.
;;;  And every check in the ask layer re-asks on a value it refuses -- a
;;;  bulge that breaks out of the envelope, a tangent radius too short to
;;;  span its two bulges -- so the second pass has to find the store
;;;  empty and let the user type the correction, rather than being
;;;  re-fed the same bad number for ever.
;;;
;;;  NOTHING GETS IN THAT COULD NOT HAVE BEEN TYPED.  A distance is
;;;  checked against the same rules initget puts on the prompt (no
;;;  negative anywhere, no zero except where zero is an answer), and a
;;;  keyword against the very list the prompt offers.  That is what
;;;  keeps NA off a question that must have an answer: OASIS asks for
;;;  every measurement as REQUIRED, so a form's nil is demoted to an
;;;  unanswered box and asked for rather than handed to arithmetic.

(setq oasis:*form* nil)

;; The question being asked, as a form key -- set by oasis:askstep for
;; each slot it asks, and nil everywhere else, which is what keeps the
;; pool-bottom flow at the end of the run out of the store.
(setq oasis:*fkey* nil)

(defun oasis:fclear () (setq oasis:*form* nil))

;; The form's answer to the question now being asked, taken OUT of the
;; store as it is read, or the symbol OASIS-NONE when the form has
;; nothing to say about it.
(defun oasis:fpull ( / p)
  (cond
    ((null oasis:*fkey*) 'OASIS-NONE)
    ((setq p (assoc oasis:*fkey* oasis:*form*))
     (setq oasis:*form* (vl-remove p oasis:*form*))
     (cdr p))
    (t 'OASIS-NONE)))

;; Which slot each answer belongs to.  Slot 1 -- the base point -- has
;; no key: it is picked in the drawing.
(setq oasis:*fkeys*
  '((0 . shape) (2 . x)   (3 . y)   (4 . rl)  (5 . rt)  (6 . rr)
    (7 . ftl)   (8 . ftr) (9 . fbc) (10 . sub) (11 . detail)
    (12 . off)  (13 . fbr)))

(defun oasis:fkeyof (k) (cdr (assoc k oasis:*fkeys*)))

;; Could V have been typed at a distance prompt of this kind?  The same
;; rules initget puts on the prompt: never negative, and never zero
;; except where ZER admits it.
(defun oasis:fdist-p (kind v)
  (and (numberp v) (or (> v 0.0) (and (eq kind 'ZER) (= v 0.0)))))

;; The word in KWS that S names, spelled the way the prompt spells it,
;; or nil.  Checked against the very list the question offers, so a
;; keyword this question never had cannot get in through the store.
(defun oasis:fkw (s kws / i n w out)
  (if (= (type s) 'STR)
      (progn
        (setq i 1 n (strlen kws) w "")
        (while (<= i (1+ n))
          (cond
            ((or (> i n) (= (substr kws i 1) " "))
             (if (and (/= w "") (= (strcase w) (strcase s))) (setq out w))
             (setq w ""))
            (t (setq w (strcat w (substr kws i 1)))))
          (setq i (1+ i)))))
  out)

;; Run OASIS with a form's answers already in hand.  Nothing happens
;; here that the direct path misses: a caller may equally set
;; oasis:*form* itself and call c:OASIS, which is what the tests do.
(defun oasis:run-with-answers (answers)
  (setq oasis:*form* answers)
  (c:OASIS)
  (oasis:fclear)
  (princ))

;;; -------------------- ask layer ---------------------------------------
;;; Copies of the CALOFIN-LIB helpers under this file's own prefix, so
;;; the standalone build loads alone (STANDARDS.md section 4).  The Back
;;; sentinel is the symbol OASIS-BACK.

;; Keyword question.  kws is the initget string, shown the bracketed
;; list, dflt the Enter answer (nil = an answer is required).  Returns
;; the keyword, or OASIS-BACK for Back/Undo.
(defun oasis:askkw (msg kws shown dflt back / v f)
  ;; the form first, and only a word this question actually offers --
  ;; spelled the way the prompt spells it, so nothing downstream can
  ;; tell a filled-in sheet from a typed answer
  (if (setq f (oasis:fkw (oasis:fpull) kws))
    f
    (progn
      (initget (if dflt 0 (if back 0 1))
               (if back (strcat kws " Back Undo") kws))
      (setq v (getkword (strcat "\n" msg " [" shown
                                (if back "/Back" "") "]"
                                (if dflt (strcat " <" dflt ">") "") ": ")))
      (cond ((member v '("Back" "Undo")) 'OASIS-BACK)
            ((null v) (if dflt dflt (oasis:askkw msg kws shown dflt back)))
            (t v)))))

;; Distance entry with the kind system of STANDARDS.md section 3:
;; REQ required, NAX/ZER accept NA, SUG offers a default.  Returns the
;; number, nil for NA, or OASIS-BACK.
(defun oasis:askdist (kind msg dflt back / v kw)
  ;; the form first.  A number this kind of question could have been
  ;; given is taken; anything else -- an NA on a REQUIRED measurement
  ;; above all -- is treated as an unanswered box and asked for, since
  ;; a nil where a distance belongs reaches arithmetic and not a check
  (setq v (oasis:fpull))
  (if (oasis:fdist-p kind v)
    v
    (progn
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
        (t v)))))

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

;;; -------------------- layers ------------------------------------------

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
;;
;; rf says which: a number is the reverse arc's radius, "SEAM" the
;; internal tangency a kidney hands over at, and a straight run is either
;; asked for by name -- "LINE", what a complex run answers a joiner
;; question with -- or implied by the shape, which is how a cloud's flat
;; bottom arrives with nothing given at all.  Both reach the same place:
;; the straight run IS the reverse arc with an infinite radius, so
;; nothing downstream has to tell the two apart.
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
    ((or (null rf) (and (= (type rf) 'STR) (= rf "LINE")))
     (setq m (oasis:extnorm c1 r1 c2 r2))
     (if m (progn (setq a (atan (cadr m) (car m)))
                  (list "LINE" m a a))))
    (t
     (setq cf (oasis:fillet c1 r1 c2 r2 rf))
     (if cf (list nil cf (angle c1 cf) (angle c2 cf))))))

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
(defun oasis:solve (w h rl rt rr ftl ftr fbc fbr off variant
                    / nm bc br bs jr js kt n i j js2 jj ok jp jn jl jm out)
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
    ;; the NXT cloud: three lobes, and the ring meets the centre one
    ;; TWICE -- it is listed twice, so the solver walks under it out to
    ;; the right lobe and back over it, and cuts two arcs from the one
    ;; circle without knowing that is what it is doing
    ((oasis:nxt-p variant)
     (setq bc (list (oasis:nxtcen w h rl 0) (oasis:nxtcen w h rt 1)
                    (oasis:nxtcen w h rr 2) (oasis:nxtcen w h rt 1))
           br (list rl rt rr rt)
           bs (list 4 5 6 5)
           jr (list fbc fbr ftr ftl)
           js (list 9 13 8 7)))
    (t
     (setq bc (list (list rl rl) (list (- w rr) rr)
                    (oasis:topcen w h rt variant off))
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
                ;; to where the joiner after it picks up.  Those two can
                ;; be the SAME point -- two straight runs either side of
                ;; a bulge that shares a tangent line with both its
                ;; neighbours touch it in one place -- and then the bulge
                ;; is a point on the outline, not an arc of it.  Nothing
                ;; is drawn for it: an ARC whose two angles are equal is
                ;; a full circle to AutoCAD, which is not what a pinched
                ;; bulge means.
                out (if (> (cal:angnorm (- (nth 2 jn) (nth 3 jp)))
                           oasis:*fuzz*)
                        (cons (list (nth (* 2 i) nm) (nth i bc) (nth i br)
                                    (nth 3 jp) (nth 2 jn) T (nth i bs))
                              out)
                        out)
                ;; then that joiner.  A seam draws nothing -- the two
                ;; arcs hand straight over at the touch point.  A reverse
                ;; arc curves the other way round its own circle, so its
                ;; two ends swap over.
                out (cond
                      ((oasis:seam-p jn) out)
                      ((and (= (type (nth 0 jn)) 'STR)
                            (= (nth 0 jn) "LINE"))
                       (setq jl (cal:v+ (nth i bc)
                                          (cal:v* (nth 1 jn) (nth i br)))
                             jm (cal:v+ (nth j bc)
                                          (cal:v* (nth 1 jn) (nth j br))))
                       ;; two bulges already tangent to each other leave
                       ;; no run between them, only the point they touch
                       (if (> (distance jl jm) oasis:*fuzz*)
                           (cons (list (nth (1+ (* 2 i)) nm) jl jm
                                       ;; a run the user asked for keeps
                                       ;; its answer slot, so backing up
                                       ;; to it still picks it out in red;
                                       ;; the one a cloud's flat bottom
                                       ;; implies was never asked and has
                                       ;; none
                                       (nth 2 jn) nil "LINE"
                                       (if (nth i jr) (nth i js)))
                                 out)
                           out))
                      ((> (cal:angnorm (- (angle (nth 1 jn) (nth i bc))
                                            (angle (nth 1 jn) (nth j bc))))
                          oasis:*fuzz*)
                       (cons (list (nth (1+ (* 2 i)) nm) (nth 1 jn)
                                   (nth i jr)
                                   (angle (nth 1 jn) (nth j bc))
                                   (angle (nth 1 jn) (nth i bc))
                                   nil (nth i js))
                             out))
                      (t out))
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

;; Where a straight run meets a circle: the up-to-two points of (c r)
;; that lie ON the segment p->q, as a list.  The segment is walked as
;; p + t(q - p) and only 0 <= t <= 1 counts, so a circle the run points
;; at but never reaches gives back nothing.
(defun oasis:seg-circ (p q c r / dx dy fx fy qa qb qc d sd out t1)
  (setq dx (- (car q) (car p))   dy (- (cadr q) (cadr p))
        fx (- (car p) (car c))   fy (- (cadr p) (cadr c))
        qa (+ (* dx dx) (* dy dy))
        qb (* 2.0 (+ (* fx dx) (* fy dy)))
        qc (- (+ (* fx fx) (* fy fy)) (* r r))
        out nil)
  (if (> qa oasis:*fuzz*)
      (progn
        (setq d (- (* qb qb) (* 4.0 qa qc)))
        (if (> d 0.0)
            (progn
              (setq sd (sqrt d))
              (foreach t1 (list (/ (+ (- qb) sd) (* 2.0 qa))
                                (/ (- (- qb) sd) (* 2.0 qa)))
                (if (and (>= t1 0.0) (<= t1 1.0))
                    (setq out (cons (list (+ (car p) (* t1 dx))
                                          (+ (cadr p) (* t1 dy)))
                                    out))))))))
  out)

;; Where two straight runs meet, or nil.  Parallel runs never do, and a
;; meeting past either segment's ends is not one.
(defun oasis:seg-seg (p q r s / ax ay bx by den t1 u)
  (setq ax  (- (car q) (car p))  ay (- (cadr q) (cadr p))
        bx  (- (car s) (car r))  by (- (cadr s) (cadr r))
        den (- (* ax by) (* ay bx)))
  (if (> (abs den) oasis:*fuzz*)
      (progn
        (setq t1 (/ (- (* (- (car r) (car p)) by)
                       (* (- (cadr r) (cadr p)) bx))
                    den)
              u  (/ (- (* (- (car r) (car p)) ay)
                       (* (- (cadr r) (cadr p)) ax))
                    den))
        (if (and (>= t1 0.0) (<= t1 1.0) (>= u 0.0) (<= u 1.0))
            (list (+ (car p) (* t1 ax)) (+ (cadr p) (* t1 ay)))))))

;; T when two ring elements meet somewhere other than the end they share.
;; Exact rather than sampled, whichever pair of kinds it is: two circles
;; meet in at most two points and a crossing is one of them inside BOTH
;; sweeps; a run meets a circle in at most two, and only the ones on the
;; segment and inside the arc's sweep count; two runs meet at most once.
;; A simple shape's only straight run lies along a bound with both its
;; bulges tangent to it, so nothing can reach it -- but a complex one's
;; runs slant across the pool, and those can be crossed like any arc.
(defun oasis:meet-p (a b / hit p)
  (setq hit nil)
  (cond
    ((and (oasis:line-p a) (oasis:line-p b))
     (setq hit (and (oasis:seg-seg (nth 1 a) (nth 2 a)
                                   (nth 1 b) (nth 2 b))
                    T)))
    ((oasis:line-p a)
     (foreach p (oasis:seg-circ (nth 1 a) (nth 2 a) (nth 1 b) (nth 2 b))
       (if (oasis:on-arc-p b (angle (nth 1 b) p)) (setq hit T))))
    ((oasis:line-p b)
     (foreach p (oasis:seg-circ (nth 1 b) (nth 2 b) (nth 1 a) (nth 2 a))
       (if (oasis:on-arc-p a (angle (nth 1 a) p)) (setq hit T))))
    (t
     (foreach p (list (oasis:circint (nth 1 a) (nth 2 a)
                                     (nth 1 b) (nth 2 b) 1.0)
                      (oasis:circint (nth 1 a) (nth 2 a)
                                     (nth 1 b) (nth 2 b) -1.0))
       (if (and p
                (oasis:on-arc-p a (angle (nth 1 a) p))
                (oasis:on-arc-p b (angle (nth 1 b) p)))
           (setq hit T)))))
  hit)

;; The pairs of ring elements that are arcs of the SAME circle running
;; over each other.  Only a shape whose ring meets a bulge twice can have
;; any: a NXT cloud's centre lobe gives two arcs of one circle, and if
;; the four fillets round it hand over in the wrong order one of those
;; arcs sweeps most of the way round and swallows the other, so the
;; outline covers part of that circle twice instead of once.
;; oasis:crossings cannot see it -- two identical circles never intersect
;; each other, they coincide -- so it is looked for on its own.
(defun oasis:overlaps (arcs / n i j a b out)
  (setq n (length arcs) i 0 out nil)
  (while (< i n)
    (setq j (1+ i))
    (while (< j n)
      (setq a (nth i arcs)
            b (nth j arcs))
      (if (and (not (oasis:line-p a))
               (not (oasis:line-p b))
               (< (distance (nth 1 a) (nth 1 b)) oasis:*fuzz*)
               (< (abs (- (nth 2 a) (nth 2 b))) oasis:*fuzz*)
               (or (< (cal:angnorm (- (nth 3 b) (nth 3 a)))
                      (- (oasis:esweep a) oasis:*fuzz*))
                   (< (cal:angnorm (- (nth 3 a) (nth 3 b)))
                      (- (oasis:esweep b) oasis:*fuzz*))))
          (setq out (cons (list (nth 0 a) (nth 0 b)) out)))
      (setq j (1+ j)))
    (setq i (1+ i)))
  (reverse out))

;; The pairs of ring elements that run through each other.  Neighbours
;; are tangent by construction and touch only at the end they share, so
;; they are skipped; anything else that meets is the outline crossing
;; itself.
(defun oasis:crossings (arcs / n i j a b pair out)
  (setq n (length arcs) i 0 out nil)
  (while (< i n)
    (setq j (1+ i))
    (while (< j n)
      (if (not (or (= j (1+ i)) (and (= i 0) (= j (1- n)))))
        (progn
          (setq a    (nth i arcs)
                b    (nth j arcs)
                pair (list (nth 0 a) (nth 0 b)))
          (if (and (not (member pair out)) (oasis:meet-p a b))
              (setq out (cons pair out)))))
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

;; The point at which the OUTLINE reaches furthest towards one bound --
;; over the arcs AS DRAWN, not the circles they are cut from, because a
;; circle can dip well past a bound where its own arc never goes.  Every
;; arc end and the compass point of every quadrant the sweep crosses is
;; tested, the same roster oasis:overruns walks, so the answer is exact.
;; which is 0 for X-min, 1 for X-max, 2 for Y-min and 3 for Y-max.
(defun oasis:extreme (arcs which / best bd a c r s sw k ang p v)
  (setq best nil bd nil)
  (foreach a arcs
    (setq c  (nth 1 a)
          r  (nth 2 a)
          s  (nth 3 a)
          sw (if (oasis:line-p a) 0.0 (cal:angnorm (- (nth 4 a) s)))
          k  -2)
    (while (< k (if (oasis:line-p a) 0 4))
      (setq ang (cond ((= k -2) s)
                      ((= k -1) (nth 4 a))
                      (t (* k (/ pi 2.0)))))
      (if (or (minusp k) (<= (cal:angnorm (- ang s)) sw))
          (progn
            (setq p (if (oasis:line-p a)
                        (nth (if (= k -2) 1 2) a)
                        (polar c ang r))
                  v (cond ((= which 0) (car p))
                          ((= which 1) (- 0.0 (car p)))
                          ((= which 2) (cadr p))
                          (t           (- 0.0 (cadr p)))))
            (if (or (null bd) (< v bd)) (setq bd v best p))))
      (setq k (1+ k))))
  best)

;; Overall X, overall Y, and a radius on each of the six arcs.  The two
;; overall dimensions are hooked to the points that actually touch the
;; envelope -- the left and right bulges' outermost points for X, the
;; top bulge's highest point and the left bulge's lowest for Y -- so
;; they measure the bounds the user was asked for, not a chord of them.
(defun oasis:dimension (arcs ents base w h lay / doff i a e md)
  (setvar "CLAYER" lay)
  (oasis:dimstyle-on oasis:*dimstyle*)
  ;; the overall two hook the points at which the OUTLINE actually
  ;; touches each bound, whichever arc holds it.  Which one that is is
  ;; the shape's business, not a fixed position in the ring: an oasis
  ;; hangs the left and the bottom on the same bulge, a NXT cloud hangs
  ;; the left and the top on its top-left lobe and the bottom on its
  ;; centre one.
  (setq doff (oasis:dimoff w h))
  (command "_.DIMLINEAR"
           (oasis:wp (oasis:extreme arcs 0) base)
           (oasis:wp (oasis:extreme arcs 1) base)
           "_H"
           (oasis:wp (list (* 0.5 w) (+ h doff)) base))
  (command "_.DIMLINEAR"
           (oasis:wp (oasis:extreme arcs 3) base)
           (oasis:wp (oasis:extreme arcs 2) base)
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

;; T when P is already in LST, to the fuzz.
(defun oasis:member-pt (p lst / hit q)
  (setq hit nil)
  (foreach q lst (if (< (distance p q) oasis:*fuzz*) (setq hit T)))
  hit)

;; Add a tie between two centres unless it is already there.  A pair of
;; bulges that happen to be ring neighbours as well would otherwise be
;; dimensioned twice, one dim on top of the other.
(defun oasis:addtie (ties p q / e hit)
  ;; a circle the ring meets twice -- a NXT cloud's centre lobe -- would
  ;; otherwise be tied to itself, which is a dimension of nothing
  (setq hit (< (distance p q) oasis:*fuzz*))
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
(defun oasis:checkdraw (arcs cbase w h lt
                        / mark cens bul uniq ties a e i n near)
  (oasis:dimstyle-on oasis:*crossstyle*)
  (setvar "CLAYER" oasis:*guidelayer*)
  (oasis:pv-box w h cbase lt)
  (setq mark (max 1.0 (/ (max w h) 90.0)))
  ;; the outline itself, so the centres have something to belong to
  (oasis:draw arcs cbase oasis:*poollayer*)
  (setvar "CLAYER" oasis:*guidelayer*)
  ;; every circle centre in ring order, and the BULGE centres again on
  ;; their own.  A straight run has no centre, so it drops out of both
  ;; and the ring closes over it.  A circle the ring meets TWICE is in
  ;; the ring order twice -- which is right for the ring ties, and wrong
  ;; for the marks and the corner ties, so those walk a deduped copy.
  (setq cens nil bul nil uniq nil)
  (foreach a arcs
    (if (not (oasis:line-p a))
        (progn
          (setq cens (cons (nth 1 a) cens))
          (if (nth 5 a) (setq bul (cons (nth 1 a) bul))))))
  (setq cens (reverse cens)
        bul  (reverse bul)
        n    (length cens)
        i    0)
  (foreach a cens
    (if (not (oasis:member-pt a uniq)) (setq uniq (cons a uniq))))
  (setq uniq (reverse uniq))
  (foreach a uniq (oasis:pv-circle a mark cbase "CONTINUOUS" nil))
  (setvar "CLAYER" oasis:*dimlayer*)
  ;; every centre back to the two corners nearest it
  (foreach a uniq
    (setq near (oasis:near2 a w h))
    (oasis:crossdim a (car near) cbase)
    (oasis:crossdim a (cadr near) cbase))
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
  (+ (* 2 (length uniq)) (length ties)))

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
;;
;; A joiner ANSWERED as a straight run needs no provisional at all: the
;; string "LINE" is an answer like any other and goes straight through.
;; The hump's offset starts at nothing, which is the shape every simple
;; run draws, so a complex run's first preview looks like the familiar
;; one until the offset is typed.
;;
;; Hands back (w h rl rt rr ftl ftr fbc off), ready for oasis:solve.
(defun oasis:fillin (ans / var w h rl rt rr cl ct cr gl gr side off g big
                         ca cd cg)
  (setq var  (oasis:variant ans)
        w    (nth 2 ans)
        h    (nth 3 ans)
        off  (cond ((nth 12 ans)) (0.0)))
  (if (oasis:nxt-p var)
      ;; three lobes sized like any other bulge, four fillets read off
      ;; the smallest of them and lifted clear of their own minimums
      (progn
        (setq side (* 0.5 oasis:*startside* (min w h))
              rl   (cond ((nth 4 ans)) (side))
              rt   (cond ((nth 5 ans)) (side))
              rr   (cond ((nth 6 ans)) (side))
              g    (* 0.6 (min rl rt rr))
              ca   (oasis:nxtcen w h rl 0)
              cd   (oasis:nxtcen w h rt 1)
              cg   (oasis:nxtcen w h rr 2))
        (list w h rl rt rr
              (cond ((nth 7 ans))  ((max g (* 1.25 (oasis:filmin cd rt
                                                                 ca rl)))))
              (cond ((nth 8 ans))  ((max g (* 1.25 (oasis:filmin cg rr
                                                                 cd rt)))))
              (cond ((nth 9 ans))  ((max g (* 1.25 (oasis:filmin ca rl
                                                                 cd rt)))))
              (cond ((nth 13 ans)) ((max g (* 1.25 (oasis:filmin cd rt
                                                                 cg rr)))))
              0.0))
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
                     (min rl rr))
              ;; the two circles the bottom joiner will actually span --
              ;; the matching pair derived on a true kidney, the two given
              ;; sides on an asymmetric one
              cl (if (= var "TrueKidney") (list g g) (list rl rl))
              gl (if (= var "TrueKidney") g rl)
              cr (if (= var "TrueKidney") (list (- w g) g) (list (- w rr) rr))
              gr (if (= var "TrueKidney") g rr))
        (list w h rl rt rr nil nil
              ;; and lifted clear of its own minimum, like every other
              ;; joiner provisional -- below it there is no fillet, and
              ;; the preview would have nothing to draw until the very
              ;; last question was answered
              (cond ((nth 9 ans))
                    ((max (* 0.6 g)
                          (* 1.25 (oasis:filmin cl gl cr gr)))))
              nil off))
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
        ct   (if rt (oasis:topcen w h rt var off))
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
              ((max g (* 1.25 (oasis:filmin cl rl cr rr)))))
        nil off)))))

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
                                (nth 6 full) (nth 7 full) (nth 8 full)
                                (nth 9 full) var)
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
  (cond ((and (= (type v) 'STR) (member v '("Back" "Undo"))) 'OASIS-BACK)
        ((null v) (list 0.0 0.0 0.0))
        (t (list (car v) (cadr v) (if (caddr v) (caddr v) 0.0)))))

;; A side bulge's radius, re-asked until it fits inside the Y bound.
;; A bulge is tangent to the bottom edge, so its top sits at twice its
;; radius: any more than half the Y bound and it breaks out of the top.
(defun oasis:ask-bulge (msg side w h / v)
  (setq v (oasis:askdist 'REQ msg nil T))
  (while (and (not (eq v 'OASIS-BACK))
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
    (setq v (oasis:askdist 'REQ msg nil T)))
  v)

;; The top bulge's radius, re-asked while it swallows a side bulge (or
;; is swallowed by one).  Nesting cannot be cured with a tangent radius
;; later, so it has to be caught here.
(defun oasis:ask-top (msg w h rl variant off / v cl ct big)
  (setq cl (list rl rl)
        v  (oasis:askdist 'REQ msg nil T))
  (while (and (not (eq v 'OASIS-BACK))
              (progn
                (setq ct  (oasis:topcen w h v variant off)
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
    (setq v (oasis:askdist 'REQ msg nil T)))
  v)

;; The Y bound.  It is asked the same way for every shape but one: a
;; TRUE kidney is the one the envelope's own proportions can rule out,
;; because its two matching sides are not given but derived.  Whatever
;; top radius they are derived from, they come out less than Y across
;; together and grow towards exactly that as the top circle grows -- so
;; they fit inside X only while Y is less than X, and on a Y that is not,
;; no top radius rescues the shape.  That is why it is caught here,
;; where the user can still change the number that caused it, rather
;; than at a radius question that would refuse every answer.
(defun oasis:ask-ybound (msg w var / v)
  (setq v (oasis:askdist 'REQ msg nil T))
  (while (and (not (eq v 'OASIS-BACK))
              (= var "TrueKidney")
              (> (+ v oasis:*fuzz*) w))
    (princ (strcat "\nA true kidney " (rtos v) " deep in a " (rtos w)
                   " envelope closes on itself -- its two matching"
                   " sides always meet"))
    (princ (strcat "\nbefore they reach the sides of the box.  Y has to"
                   " be less than X here; an asymmetric kidney takes any"
                   " envelope."))
    (setq v (oasis:askdist 'REQ msg nil T)))
  v)

;; A true kidney's top-center radius, re-asked until a kidney can be
;; built on it.  Below a minimum the top circle cannot reach both sides
;; -- at the minimum it passes through the two bottom corners and the
;; matching sides shrink to nothing.  There is no maximum to check
;; against: the derived sides never span more than Y together, and
;; oasis:ask-ybound has already turned away any Y that is not less
;; than X.
(defun oasis:ask-ktop (msg w h / v r)
  (setq v (oasis:askdist 'REQ msg nil T))
  (while (and (not (eq v 'OASIS-BACK))
              (null (setq r (if (> v (+ (oasis:ktrue-min w h) oasis:*fuzz*))
                                (oasis:ktrue-side w h v)))))
    (princ (strcat "\nA " (rtos v) " top circle cannot reach both"
                   " sides of a " (rtos w) " x " (rtos h)
                   " envelope -- it has to be more than "
                   (rtos (oasis:ktrue-min w h)) "."))
    (setq v (oasis:askdist 'REQ msg nil T)))
  v)

;; A joiner answer on a COMPLEX run: a radius as usual, or the keyword
;; Line for the straight run between the two bulges' tangent points.
;; Returns the number, the string "LINE", or OASIS-BACK.  Its own
;; getdist rather than oasis:askdist because that one folds every
;; keyword but Back into nil, which is the answer a cloud's implied flat
;; bottom already means.
(defun oasis:askrun (msg / v)
  ;; the form answers this one two ways -- a radius, or the word Line
  ;; for the straight run -- and neither reaches here as anything the
  ;; typed path would not also produce
  (setq v (oasis:fpull))
  (cond
    ((oasis:fdist-p 'REQ v) v)
    ((oasis:fkw v "Line") "LINE")
    (t
     (initget 7 "Line Back Undo")
     (setq v (getdist (strcat "\n" msg " [Line/Back]: ")))
     (cond ((and (= (type v) 'STR) (member v '("Back" "Undo"))) 'OASIS-BACK)
           ((= (type v) 'STR) "LINE")
           (t v)))))

;; A signed distance, defaulting to none: zero and negative are both
;; ordinary answers here, where every other measurement in the file
;; refuses them.  Returns the number or OASIS-BACK.
(defun oasis:askoff (msg / v)
  ;; the one measurement in the file where a negative and a zero are
  ;; both ordinary answers, so a form's number is taken as it stands
  (setq v (oasis:fpull))
  (if (numberp v)
    v
    (progn
      (initget 0 "Back Undo")
      (setq v (getdist (strcat "\n" msg " [Back] <0>: ")))
      (cond ((and (= (type v) 'STR) (member v '("Back" "Undo"))) 'OASIS-BACK)
            ((null v) 0.0)
            (t v)))))

;; A tangent radius, re-asked until it is big enough to span its two
;; bulges.  Below the minimum the two circles it would have to touch
;; never meet, and there is no such arc at any position.  runs is T on a
;; complex pool, where Line is an answer too -- and the only thing that
;; can rule THAT out is one bulge lying inside the other, since a
;; straight run has no radius to be too small.
(defun oasis:ask-tangent (msg c1 r1 c2 r2 runs / v mn bad)
  (setq mn (oasis:filmin c1 r1 c2 r2)
        v  (if runs (oasis:askrun msg) (oasis:askdist 'REQ msg nil T)))
  (while (and (not (eq v 'OASIS-BACK))
              (setq bad
                    (if (= (type v) 'STR)
                        (if (null (oasis:extnorm c1 r1 c2 r2)) "nested")
                        (if (<= v (+ mn oasis:*fuzz*)) "short"))))
    (if (= bad "short")
        (princ (strcat "\n" (rtos v) " is too short to reach from one bulge"
                       " to the other -- it has to be more than "
                       (rtos mn) "."))
        (princ (strcat "\nOne of those two bulges lies inside the other,"
                       " so there is no straight run between them.")))
    (setq v (if runs (oasis:askrun msg) (oasis:askdist 'REQ msg nil T))))
  v)

;; How far a complex Center pool's hump is off centre, re-asked while it
;; would put the hump somewhere there is no pool.  Two ways it can: past
;; either end of the envelope, where the "top" bulge is no longer over
;; the water at all, or so far across that it swallows the left bulge --
;; a nesting no tangent radius can bridge, exactly as oasis:ask-top
;; refuses on the centred one.  Reaching past a bound is NOT refused:
;; that is an ordinary trimmed hump, and oasis:report-extents names it.
(defun oasis:ask-offset (msg w h rl rt / v ct bad)
  (setq v (oasis:askoff msg))
  (while (and (not (eq v 'OASIS-BACK))
              (progn
                (setq ct  (oasis:topcen w h rt "Center" v)
                      bad (cond ((or (< (car ct) 0.0) (> (car ct) w)) "out")
                                ((oasis:nested-p ct rt (list rl rl) rl)
                                 "nested")))
                bad))
    (if (= bad "out")
        (princ (strcat "\nThat puts the hump's centre at "
                       (rtos (car ct)) ", off the " (rtos w)
                       " envelope altogether -- it has to stay on it."))
        (princ (strcat "\nAt " (rtos v) " off centre the hump and the left"
                       " bulge lie one inside the other, so no tangent"
                       " radius can join them.")))
    (setq v (oasis:askoff msg)))
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
(defun oasis:askstep (k ans / var v w h rl rt rr cl ct cr ca cd cg off
                          runs)
  ;; which answer the question about to be asked fills, so the ask
  ;; helpers under it can look it up in the form.  Set for every slot,
  ;; including the ones no form answers, so a stale key cannot survive
  ;; into the next question.
  (setq oasis:*fkey* (oasis:fkeyof k))
  (setq var  (oasis:variant ans)
        w    (nth 2 ans) h  (nth 3 ans)
        rl   (oasis:leftrad var h (nth 4 ans))
        rt   (nth 5 ans) rr (nth 6 ans)
        off  (nth 12 ans)
        ;; on a complex run every joiner question takes Line as well
        runs (oasis:complex-p ans))
  ;; a true kidney's sides are derived from its top circle, so by the
  ;; time the bottom joiner is asked for they are known without ever
  ;; having been asked about
  (if (and (= var "TrueKidney") w h rt)
      (setq rl (oasis:ktrue-side w h rt)
            rr rl))
  (setq cl  (if (and w h rl) (list rl rl))
        ct  (if (and w h rt (not (oasis:kidney-p var)))
                (oasis:topcen w h rt var off))
        cr  (if (and w h rr) (list (- w rr) rr))
        ;; a NXT cloud's three lobes sit nowhere near the other shapes'
        ;; left/right/top, so they get their own three
        ca  (if (and w h rl (oasis:nxt-p var)) (oasis:nxtcen w h rl 0))
        cd  (if (and w h rt (oasis:nxt-p var)) (oasis:nxtcen w h rt 1))
        cg  (if (and w h rr (oasis:nxt-p var)) (oasis:nxtcen w h rr 2)))
  (cond
    ;; CLoud takes two capitals because Center already has the C.  The
    ;; keyword comes back spelled that way, so it is normalized here and
    ;; nothing downstream ever sees it.
    ((= k 0)
     (setq v (oasis:askkw "Which shape is it?"
                          "Center TopRight CLoud Kidney NXTcloud"
                          "Center/TopRight/CLoud/Kidney/NXTcloud"
                          "Center" nil))
     (if (= v "CLoud") "Cloud" v))
    ((= k 10)
     (if (= (nth 0 ans) "Kidney")
         (oasis:askkw "Kidney type?" "True Asymmetric"
                      "True/Asymmetric" "True" T)
         (oasis:askkw "Cloud bottom?" "Straight Rounded"
                      "Straight/Rounded" "Straight" T)))
    ;; simple is the shape as it has always been; complex opens the two
    ;; things a drawing sometimes has and the plain flow cannot say --
    ;; a straight run in place of any joiner, and a hump off centre
    ((= k 11)
     (oasis:askkw "Simple or complex?" "Simple Complex"
                  "Simple/Complex" "Simple" T))
    ((= k 1) (oasis:askbase T))
    ((= k 2) (oasis:askdist 'REQ "X - overall left-to-right bounds" nil T))
    ((= k 3) (oasis:ask-ybound "Y - overall front-to-back bounds" w var))
    ((= k 4) (oasis:ask-bulge (oasis:sprompt var 4)
                              (if (oasis:nxt-p var) "top-left" "left") w h))
    ((= k 5) (cond ((oasis:nxt-p var)
                    (oasis:ask-bulge (oasis:sprompt var 5) "center" w h))
                   ((oasis:kidney-p var)
                    (oasis:ask-ktop (oasis:sprompt var 5) w h))
                   ((oasis:ask-top (oasis:sprompt var 5) w h rl var off))))
    ((= k 6) (oasis:ask-bulge (oasis:sprompt var 6) "right" w h))
    ;; on a cloud the top joiner runs straight from the right bulge back
    ;; to the left one; on an oasis it stops at the third bulge first;
    ;; on a NXT cloud every joiner runs between two of the three lobes
    ((= k 7) (cond ((oasis:nxt-p var)
                    (oasis:ask-tangent (oasis:sprompt var 7) cd rt ca rl
                                       runs))
                   ((oasis:cloud-p var)
                    (oasis:ask-tangent (oasis:sprompt var 7) cr rr cl rl
                                       runs))
                   ((oasis:ask-tangent (oasis:sprompt var 7) ct rt cl rl
                                       runs))))
    ((= k 8) (if (oasis:nxt-p var)
                 (oasis:ask-tangent (oasis:sprompt var 8) cg rr cd rt runs)
                 (oasis:ask-tangent (oasis:sprompt var 8) cr rr ct rt runs)))
    ((= k 9) (if (oasis:nxt-p var)
                 (oasis:ask-tangent (oasis:sprompt var 9) ca rl cd rt runs)
                 (oasis:ask-tangent (oasis:sprompt var 9) cl rl cr rr runs)))
    ((= k 12) (oasis:ask-offset (oasis:sprompt var 12) w h rl rt))
    ((= k 13) (oasis:ask-tangent (oasis:sprompt var 13) cd rt cg rr runs))))

;; The lobe a NXT cloud's right one lies inside, or swallows, or nil.
;; Its three are pinned by the envelope, so two of them can end up nested
;; with no tangent radius able to bridge them, exactly as on the oasis
;; shapes -- and the right lobe is the last of the three asked, so it is
;; where the pair shows up.  The other pair, the centre lobe inside the
;; top-left one, needs the top-left lobe at exactly half of a square
;; envelope, and there it swallows the right lobe as well, so this catches
;; that too.
(defun oasis:nxt-nests (w h rl rt rr / ca cd cg)
  (setq ca (oasis:nxtcen w h rl 0)
        cd (oasis:nxtcen w h rt 1)
        cg (oasis:nxtcen w h rr 2))
  (cond ((oasis:nested-p cg rr ca rl) "top-left")
        ((oasis:nested-p cg rr cd rt) "center")))

;; The right bulge is the last of the three, so it is the one that has
;; to be checked against BOTH of the others before the tangent radii are
;; asked for.  Returns the name of the bulge it nests with, or nil.
(defun oasis:right-nests (w h rl rt rr off variant / cl ct cr)
  (setq rl (oasis:leftrad variant h rl)
        cl (list rl rl)
        cr (list (- w rr) rr))
  (cond ((oasis:nested-p cr rr cl rl) "left")
        ((oasis:cloud-p variant) nil)
        ((progn (setq ct (oasis:topcen w h rt variant off))
                (oasis:nested-p cr rr ct rt))
         "top")))

;;; -------------------- walking the outline ------------------------------
;;; The bottom of the pool is laid out ON the perimeter, so everything
;;; below needs to be able to say where a point is along it.  The ring is
;;; a closed curve, so one number does it: the arc length S from the
;;; start of element 0, running the way the outline runs.
;;;
;;; That direction is not the same as an arc's own: a BULGE is walked
;;; counter-clockwise from its start angle to its end, a REVERSE arc the
;;; other way (its centre is outside the pool, so the outline goes round
;;; it clockwise), and a straight run from its first end to its second.
;;; Every element also knows which way is INTO the water, which is what
;;; an offset is measured along -- towards the centre on a bulge, away
;;; from it on a reverse arc, and across a run.

;; The angle one element sweeps, 0 for a straight run.
(defun oasis:esweep (a)
  (if (oasis:line-p a) 0.0 (cal:angnorm (- (nth 4 a) (nth 3 a)))))

;; How long one element is along the walk.
(defun oasis:elen (a)
  (if (oasis:line-p a)
      (distance (nth 1 a) (nth 2 a))
      (* (nth 2 a) (oasis:esweep a))))

;; The whole way round.
(defun oasis:ringlen (arcs / s a)
  (setq s 0.0)
  (foreach a arcs (setq s (+ s (oasis:elen a))))
  s)

;; Where element A is at fraction U of its own walk, as
;; (point . inward-angle) -- inward being the way an offset is measured.
(defun oasis:eat (a u / th)
  (if (oasis:line-p a)
      (cons (cal:v+ (nth 1 a)
                      (cal:v* (mapcar '- (nth 2 a) (nth 1 a)) u))
            (cal:angnorm (+ (nth 3 a) pi)))
      (progn
        ;; a bulge runs with the angle, a reverse arc against it
        (setq th (if (nth 5 a)
                     (+ (nth 3 a) (* u (oasis:esweep a)))
                     (- (nth 4 a) (* u (oasis:esweep a)))))
        (cons (polar (nth 1 a) th (nth 2 a))
              ;; the centre is inside the pool on a bulge and outside it
              ;; on a reverse arc, so the two point opposite ways
              (cal:angnorm (if (nth 5 a) (+ th pi) th))))))

;; The point at arc length S round the ring, as
;; (point inward-angle element-index fraction).  S wraps.
(defun oasis:ringat (arcs s / tot i n a l u pu out)
  (setq tot (oasis:ringlen arcs)
        n   (length arcs)
        i   0)
  (while (< s 0.0) (setq s (+ s tot)))
  (while (>= s tot) (setq s (- s tot)))
  (while (and (< i n) (null out))
    (setq a (nth i arcs)
          l (oasis:elen a))
    (if (or (<= s l) (= i (1- n)))
        (setq u   (if (> l oasis:*fuzz*) (/ s l) 0.0)
              pu  (oasis:eat a u)
              out (list (car pu) (cdr pu) i u))
        (setq s (- s l)))
    (setq i (1+ i)))
  out)

;; A list of numbers in ascending order, without duplicates closer
;; together than the fuzz -- a crossing that lands exactly on a joint is
;; found by both elements that meet there, and it is one crossing.
(defun oasis:sortasc (lst / out v p taken)
  (setq out nil taken nil)
  (while
    (progn
      (setq p nil)
      (foreach v lst
        (if (and (or (null taken) (> v (+ taken oasis:*fuzz*)))
                 (or (null p) (< v p)))
            (setq p v)))
      p)
    (setq out   (cons p out)
          taken p))
  (reverse out))

;; The arc length at which each element STARTS -- and so, one per
;; element, the arc length of every change of tangency round the ring.
(defun oasis:joints (arcs / s out a)
  (setq s 0.0 out nil)
  (foreach a arcs
    (setq out (cons s out)
          s   (+ s (oasis:elen a))))
  (reverse out))

;; The arc length of the point on the ring nearest P.
(defun oasis:ringnear (arcs p / s best bd i n a l u q d dx dy dd)
  (setq s 0.0 best 0.0 bd nil i 0 n (length arcs))
  (while (< i n)
    (setq a (nth i arcs)
          l (oasis:elen a))
    (if (oasis:line-p a)
        (setq dx (- (car (nth 2 a)) (car (nth 1 a)))
              dy (- (cadr (nth 2 a)) (cadr (nth 1 a)))
              dd (+ (* dx dx) (* dy dy))
              u  (if (> dd oasis:*fuzz*)
                     (/ (+ (* (- (car p) (car (nth 1 a))) dx)
                           (* (- (cadr p) (cadr (nth 1 a))) dy))
                        dd)
                     0.0))
        (setq u (if (> (oasis:esweep a) oasis:*fuzz*)
                    (/ (cal:angnorm
                         (if (nth 5 a)
                             (- (angle (nth 1 a) p) (nth 3 a))
                             (- (nth 4 a) (angle (nth 1 a) p))))
                       (oasis:esweep a))
                    0.0)))
    (setq u (max 0.0 (min 1.0 u))
          q (car (oasis:eat a u))
          d (distance p q))
    (if (or (null bd) (< d bd)) (setq bd d best (+ s (* u l))))
    (setq s (+ s l)
          i (1+ i)))
  best)

;; Every arc length at which the ring crosses the straight line through Q
;; with unit normal NRM, in ascending order.  Exact: a run is linear in
;; its own parameter, and an arc meets a line where its angle is one of
;; two the normal names -- no walking and no sampling.
(defun oasis:ringcut (arcs q nrm / s out i n a l d0 dx dy den u ph c th)
  (setq s 0.0 out nil i 0 n (length arcs))
  (while (< i n)
    (setq a  (nth i arcs)
          l  (oasis:elen a)
          d0 (+ (* (- (car (nth 1 a)) (car q)) (car nrm))
                (* (- (cadr (nth 1 a)) (cadr q)) (cadr nrm))))
    (if (oasis:line-p a)
        (progn
          (setq dx  (- (car (nth 2 a)) (car (nth 1 a)))
                dy  (- (cadr (nth 2 a)) (cadr (nth 1 a)))
                den (+ (* dx (car nrm)) (* dy (cadr nrm))))
          (if (> (abs den) oasis:*fuzz*)
              (progn
                (setq u (/ (- d0) den))
                (if (and (>= u 0.0) (<= u 1.0))
                    (setq out (cons (+ s (* u l)) out))))))
        (progn
          (setq c (/ (- d0) (nth 2 a)))
          (if (<= (abs c) 1.0)
              (progn
                (setq ph (atan (cadr nrm) (car nrm)))
                (foreach th (list (+ ph (atan (sqrt (max 0.0 (- 1.0 (* c c))))
                                              c))
                                  (- ph (atan (sqrt (max 0.0 (- 1.0 (* c c))))
                                              c)))
                  (setq u (if (> (oasis:esweep a) oasis:*fuzz*)
                              (/ (cal:angnorm
                                   (if (nth 5 a)
                                       (- th (nth 3 a))
                                       (- (nth 4 a) th)))
                                 (oasis:esweep a))))
                  (if (and u (<= u 1.0))
                      (setq out (cons (+ s (* u l)) out))))))))
    (setq s (+ s l)
          i (1+ i)))
  (oasis:sortasc out))

;;; -------------------- the pool bottom ----------------------------------
;;; The floor, laid out on the perimeter the questions have just built --
;;; ABHD's bottom flow, with ABHD's one input replaced.  There it is a
;;; survey: points are picked on the pool edge and everything is measured
;;; from the nearest one.  Here the perimeter is not surveyed but KNOWN,
;;; exactly, so a point on it can be said three ways:
;;;
;;;   Tangency  every change of tangency round the outline is numbered
;;;             and drawn on screen while the question is up -- the
;;;             joints between the arcs, which are the places a pool
;;;             is naturally broken at.  Name a number.
;;;   Nearest   pick anywhere; the pick is dropped onto the outline at
;;;             the nearest point of it, exactly.
;;;   Offset    say how far in from one of the four bounds, and the
;;;             break is where that line crosses the pool -- one answer
;;;             for both ends of the break, which is how a deep end is
;;;             usually called out ("the hopper starts 12 feet in").
;;;
;;; What is drawn is ABHD's: a SHALLOW BREAK across the pool where the
;;; flat shallow floor starts to fall, a DEEP BREAK where it levels out,
;;; the HOPPER beyond it -- the flat deep floor, the perimeter offset
;;; inward -- and a SLOPE LINE up each side from the hopper's corner to
;;; the shallow break.  The deep break goes down as three collinear
;;; pieces, dashed stubs from each wall in to the hopper's corners with a
;;; solid run between them, and carries the classic K/L/M string of
;;; chained dimensions a stand-off clear of it on the shallow side.
;;;
;;; One thing is not ABHD's.  ABHD asks three offsets -- one at each end
;;; of the deep break and one at the back -- and blends them along the
;;; wall, because a surveyed shape is irregular and the tape says
;;; different things in different places.  An oasis is a designed shape,
;;; so its hopper is ONE offset, and that buys exactness: offsetting a
;;; tangent-continuous ring inward by a constant is again a
;;; tangent-continuous ring, with the same centres, the same angles, and
;;; every bulge shrunk and every reverse arc grown by the offset.  The
;;; hopper is that ring cut off at the deep break, so it is arcs and
;;; runs, not a polyline of facets, and its corners are exactly where it
;;; meets the break.  The K/L/M string then reads what the offset really
;;; produced at the break rather than the number that was typed.

;; One ring element pushed inward by OFF.  A bulge curves away from the
;; water, so it shrinks; a reverse arc curves into it, so it grows; a
;; straight run simply moves across.  The result meets its neighbours at
;; the same normals it did, which is why the offset ring is still
;; tangent-continuous.
(defun oasis:offel (a off)
  (if (oasis:line-p a)
      (list (nth 0 a)
            (polar (nth 1 a) (+ (nth 3 a) pi) off)
            (polar (nth 2 a) (+ (nth 3 a) pi) off)
            (nth 3 a) nil "LINE" nil)
      (list (nth 0 a) (nth 1 a)
            (if (nth 5 a) (- (nth 2 a) off) (+ (nth 2 a) off))
            (nth 3 a) (nth 4 a) (nth 5 a) nil)))

;; The first bulge an offset of OFF would swallow, or nil.  Past its own
;; radius a bulge has no offset left to give and the hopper cannot be
;; built at all -- there is no arc on the other side of it.
(defun oasis:offbad (arcs off / bad a)
  (setq bad nil)
  (foreach a arcs
    (if (and (null bad) (not (oasis:line-p a)) (nth 5 a)
             (<= (- (nth 2 a) off) oasis:*fuzz*))
        (setq bad (nth 0 a))))
  bad)

;; The whole ring pushed inward by OFF, or nil when a bulge would go.
(defun oasis:offring (arcs off / out a)
  (if (oasis:offbad arcs off)
      nil
      (progn
        (setq out nil)
        (foreach a arcs (setq out (cons (oasis:offel a off) out)))
        (reverse out))))

;; One ring element cut down to the stretch between fractions U0 and U1
;; of its own walk.  An arc keeps its centre and its radius; only the two
;; angles move, and which end each fraction lands on depends on which way
;; the walk runs -- with the angle on a bulge, against it on a reverse.
(defun oasis:trimel (a u0 u1 / sw)
  (if (oasis:line-p a)
      (list (nth 0 a) (car (oasis:eat a u0)) (car (oasis:eat a u1))
            (nth 3 a) nil "LINE" nil)
      (progn
        (setq sw (oasis:esweep a))
        (if (nth 5 a)
            (list (nth 0 a) (nth 1 a) (nth 2 a)
                  (cal:angnorm (+ (nth 3 a) (* u0 sw)))
                  (cal:angnorm (+ (nth 3 a) (* u1 sw)))
                  (nth 5 a) nil)
            (list (nth 0 a) (nth 1 a) (nth 2 a)
                  (cal:angnorm (- (nth 4 a) (* u1 sw)))
                  (cal:angnorm (- (nth 4 a) (* u0 sw)))
                  (nth 5 a) nil)))))

;; How far it is round the ring from SA forward to SB.
(defun oasis:spanlen (arcs sa sb / tot d)
  (setq tot (oasis:ringlen arcs)
        d   (- sb sa))
  (while (< d 0.0) (setq d (+ d tot)))
  (while (>= d tot) (setq d (- d tot)))
  d)

;; The stretch of the ring from SA forward to SB, as ring elements with
;; the first and last trimmed -- an OPEN chain, drawable by oasis:draw
;; like any other.
(defun oasis:subring (arcs sa sb / n at k u0 want l avail u1 out guard)
  (setq n     (length arcs)
        at    (oasis:ringat arcs sa)
        k     (nth 2 at)
        u0    (nth 3 at)
        want  (oasis:spanlen arcs sa sb)
        out   nil
        guard 0)
  (while (and (> want oasis:*fuzz*) (< guard (* 4 n)))
    (setq l     (oasis:elen (nth k arcs))
          avail (* l (- 1.0 u0)))
    (if (<= want (+ avail oasis:*fuzz*))
        (setq u1   (if (> l oasis:*fuzz*) (min 1.0 (+ u0 (/ want l))) 1.0)
              out  (cons (oasis:trimel (nth k arcs) u0 u1) out)
              want 0.0)
        (setq out  (if (> avail oasis:*fuzz*)
                       (cons (oasis:trimel (nth k arcs) u0 1.0) out)
                       out)
              want (- want avail)
              k    (if (= k (1- n)) 0 (1+ k))
              u0   0.0))
    (setq guard (1+ guard)))
  (reverse out))

;; The stretch from SA to SB as a run of N+1 points, each pushed in by an
;; offset easing from O0 to O1 over the walk.  Where the offset varies
;; there is no exact curve to draw -- a slope line running out to nothing
;; at the shallow break is the case -- so it goes down as a polyline.
(defun oasis:chordrun (arcs sa sb o0 o1 n / len i out at f)
  (setq len (oasis:spanlen arcs sa sb)
        i   0
        out nil)
  (while (<= i n)
    (setq f   (/ (float i) (float n))
          at  (oasis:ringat arcs (+ sa (* len f)))
          out (cons (polar (car at) (cadr at) (+ o0 (* (- o1 o0) f))) out)
          i   (1+ i)))
  (reverse out))

;; How far the ring reaches beyond the break line through MID along U,
;; over the LEN of walk starting at SA, and where.  Returns
;; (arc-length . reach).
(defun oasis:reach (arcs sa len mid u n / i s at d best bd)
  (setq i  0
        bd nil)
  (while (<= i n)
    (setq s  (+ sa (* len (/ (float i) (float n))))
          at (oasis:ringat arcs s)
          d  (+ (* (- (car (car at)) (car mid)) (car u))
                (* (- (cadr (car at)) (cadr mid)) (cadr u))))
    (if (or (null bd) (> d bd)) (setq bd d best s))
    (setq i (1+ i)))
  (cons best bd))

;; The unit vector square to the deep break, pointing AWAY from the
;; shallow break -- the direction the hopper lies in.
(defun oasis:deepdir (p1 p2 q / u)
  (setq u (list (- (cadr p2) (cadr p1)) (- (car p1) (car p2))))
  (setq u (cal:v* u (/ 1.0 (max oasis:*fuzz* (distance '(0.0 0.0) u)))))
  (if (> (+ (* (- (car q) (car p1)) (car u))
            (* (- (cadr q) (cadr p1)) (cadr u)))
         0.0)
      (cal:v* u -1.0)
      u))

;; Where the hopper starts and stops on the OFFSET ring: the two places
;; it crosses the deep break line either side of its deepest point.
;; Returns (from to deepest), or nil when the offset ring never reaches
;; the break -- an offset so big the deep end has closed up.
(defun oasis:hopcut (offall q nrm mid u / cuts tot far ca cb c)
  (setq cuts (oasis:ringcut offall q nrm)
        tot  (oasis:ringlen offall))
  (if (< (length cuts) 2)
      nil
      (progn
        (setq far (car (oasis:reach offall 0.0 tot mid u oasis:*hopscan*))
              ca  nil
              cb  nil)
        (foreach c cuts
          (if (and (<= c far) (or (null ca) (> c ca))) (setq ca c))
          (if (and (>= c far) (or (null cb) (< c cb))) (setq cb c)))
        ;; the deepest point can sit past the last crossing, in which
        ;; case the hopper wraps the start of the ring
        (if (null ca) (setq ca (last cuts)))
        (if (null cb) (setq cb (car cuts)))
        (if (< (oasis:spanlen offall ca cb) oasis:*fuzz*)
            nil
            (list ca cb far)))))

;;; -------------------- the bottom, asked ---------------------------------

;; Every change of tangency, numbered on screen, so one can be named.
;; Scaffolding: the marks go when the flow does, like the preview.
(defun oasis:tangmarks (arcs w h base lt / out js i n at hgt mk)
  (setq js  (oasis:joints arcs)
        n   (length js)
        i   0
        hgt (/ (max w h) 34.0)
        mk  (/ (max w h) 150.0)
        out nil)
  (while (< i n)
    (setq at  (oasis:ringat arcs (nth i js))
          out (cons (oasis:pv-circle (car at) mk base "CONTINUOUS" T) out)
          ;; the number sits OUTSIDE the water, clear of the outline
          out (cons (oasis:pv-text (polar (car at)
                                          (+ (cadr at) pi)
                                          (* 1.6 hgt))
                                   hgt (itoa (1+ i)) base T)
                    out)
          i   (1+ i)))
  out)

;; A tangency change, by number.  Returns its arc length, or OASIS-BACK.
(defun oasis:asktang (msg arcs / js n v)
  (setq js (oasis:joints arcs)
        n  (length js)
        v  nil)
  (while (null v)
    (initget 7 "Back Undo")
    (setq v (getint (strcat "\n" msg " -- tangency change 1-" (itoa n)
                            " [Back]: ")))
    (cond ((and (= (type v) 'STR) (member v '("Back" "Undo")))
           (setq v 'OASIS-BACK))
          ((and (= (type v) 'INT) (<= v n)))
          (t (princ (strcat "\nThere are " (itoa n) " changes of tangency"
                            " round this pool; that is not one of them."))
             (setq v nil))))
  (if (eq v 'OASIS-BACK) v (nth (1- v) js)))

;; A point picked anywhere, dropped onto the outline at the nearest point
;; of it.  Returns its arc length, or OASIS-BACK.
(defun oasis:asknear (msg arcs base / v)
  (initget 1 "Back Undo")
  (setq v (getpoint (strcat "\n" msg " [Back]: ")))
  (if (and (= (type v) 'STR) (member v '("Back" "Undo")))
      'OASIS-BACK
      (oasis:ringnear arcs (list (- (car v) (car base))
                                 (- (cadr v) (cadr base))))))

;; A line parallel to one bound of the envelope, a given distance in from
;; it.  Returns (point normal), or OASIS-BACK.
(defun oasis:askbound (msg w h / side d)
  ;; BOttom takes two capitals because Back already has the B
  (setq side (oasis:askkw (strcat msg " -- in from which bound?")
                          "Left Right BOttom Top"
                          "Left/Right/BOttom/Top" "BOttom" T))
  (if (eq side 'OASIS-BACK)
      side
      (progn
        (setq d (oasis:askdist 'REQ (strcat "How far in from the "
                                            (strcase side T) " bound")
                               nil T))
        (if (eq d 'OASIS-BACK)
            d
            (cond ((= side "Left")    (list (list d 0.0) '(1.0 0.0)))
                  ((= side "Right")   (list (list (- w d) 0.0) '(1.0 0.0)))
                  ((= side "BOttom")  (list (list 0.0 d) '(0.0 1.0)))
                  (t                  (list (list 0.0 (- h d))
                                            '(0.0 1.0))))))))

;; One break, both ends, said whichever of the three ways suits.  Returns
;; (s1 s2) as arc lengths round the outline, or OASIS-BACK.
(defun oasis:askbreak (what arcs w h base / how ln cuts a b)
  (setq a nil)
  (while (null a)
    (setq how (oasis:askkw (strcat what " break, located how?")
                           "Offset Tangency Nearest"
                           "Offset/Tangency/Nearest" "Offset" T))
    (cond
      ((eq how 'OASIS-BACK) (setq a how))
      ;; one answer gives both ends: the break is the chord that line cuts
      ((= how "Offset")
       (setq ln (oasis:askbound (strcat "The " (strcase what T) " break")
                                w h))
       (cond
         ((eq ln 'OASIS-BACK) (setq a ln))
         (t (setq cuts (oasis:ringcut arcs (car ln) (cadr ln)))
            ;; a pool whose edge dips can be crossed more than twice by
            ;; one line -- the break is the full width of it, so the two
            ;; outermost crossings are the ones wanted, and the rest are
            ;; the dip the break runs over
            (cond
              ((< (length cuts) 2)
               (princ (strcat "\nThat line does not cross the pool at all,"
                              " so it does not name a break.")))
              (t (if (> (length cuts) 2)
                     (princ (strcat "\n(that line crosses the outline "
                                    (itoa (length cuts)) " times -- the"
                                    " break is taken right across, from the"
                                    " first to the last)")))
                 (setq a (list (car cuts) (last cuts))))))))
      ((= how "Tangency")
       (setq a (oasis:asktang (strcat "The " (strcase what T)
                                      " break, first end") arcs))
       (if (not (eq a 'OASIS-BACK))
           (progn
             (setq b (oasis:asktang (strcat "The " (strcase what T)
                                            " break, second end") arcs))
             (if (eq b 'OASIS-BACK)
                 (setq a nil)
                 (setq a (list a b))))))
      (t
       (setq a (oasis:asknear (strcat "The " (strcase what T)
                                      " break, first end") arcs base))
       (if (not (eq a 'OASIS-BACK))
           (progn
             (setq b (oasis:asknear (strcat "The " (strcase what T)
                                            " break, second end")
                                    arcs base))
             (if (eq b 'OASIS-BACK)
                 (setq a nil)
                 (setq a (list a b)))))))
    ;; two ends in the same place are not a break
    (if (and a (listp a)
             (< (distance (car (oasis:ringat arcs (car a)))
                          (car (oasis:ringat arcs (cadr a))))
                oasis:*fuzz*))
        (progn
          (princ "\nBoth ends of that break land on the same point.")
          (setq a nil))))
  a)

;;; -------------------- the bottom, built and drawn -----------------------

;; Everything the bottom is made of, worked out from the two breaks and
;; the one offset.  Returns
;;
;;   (hopper cs ce pda pdb qsa qsb ssa sda ssb sdb backw backh)
;;
;; where the hopper is a chain of ring elements, cs and ce its two
;; corners on the deep break line, pda / pdb the deep break's own two
;; ends -- pda first in the hopper's own walk -- qsa / qsb the shallow
;; break ends paired with them, ssa / sda / ssb / sdb their arc lengths,
;; and backw / backh the wall and hopper points at the back, which is
;; where the offset is worth dimensioning.  A string instead of a list is
;; the reason it cannot be built.
(defun oasis:bottom (arcs sh1 sh2 sd1 sd2 off
                     / p1 p2 q1 q2 pmid qmid u bad offall cut hop
                       ca cb cs ce da db pda pdb ssa ssb qsa qsb bp backh
                       backw r12 r21)
  (setq p1   (car (oasis:ringat arcs sd1))
        p2   (car (oasis:ringat arcs sd2))
        q1   (car (oasis:ringat arcs sh1))
        q2   (car (oasis:ringat arcs sh2))
        pmid (list (* 0.5 (+ (car p1) (car p2)))
                   (* 0.5 (+ (cadr p1) (cadr p2))))
        qmid (list (* 0.5 (+ (car q1) (car q2)))
                   (* 0.5 (+ (cadr q1) (cadr q2))))
        ;; u is square to the deep break and points away from the
        ;; shallow one, so it is also that break line's own normal --
        ;; which is what a cut of the ring is asked for by
        u    (oasis:deepdir p1 p2 qmid))
  ;; which way round the ring is the deep end?  the stretch that reaches
  ;; furthest away from the shallow break
  (setq r12 (cdr (oasis:reach arcs sd1 (oasis:spanlen arcs sd1 sd2)
                              pmid u oasis:*hopscan*))
        r21 (cdr (oasis:reach arcs sd2 (oasis:spanlen arcs sd2 sd1)
                              pmid u oasis:*hopscan*)))
  (if (>= r12 r21)
      (setq da sd1 db sd2 pda p1 pdb p2)
      (setq da sd2 db sd1 pda p2 pdb p1))
  ;; the shallow end on each side is the one nearest that deep end
  ;; walking AWAY from the hopper -- backwards, since the hopper runs
  ;; forwards from da
  (if (<= (oasis:spanlen arcs sh1 da) (oasis:spanlen arcs sh2 da))
      (setq ssa sh1 qsa q1 ssb sh2 qsb q2)
      (setq ssa sh2 qsa q2 ssb sh1 qsb q1))
  (cond
    ;; a shallow break on the far side of the deep one is the two of them
    ;; the wrong way round: the slope lines would have to run through the
    ;; hopper to reach it
    ((or (> (+ (* (- (car q1) (car pmid)) (car u))
               (* (- (cadr q1) (cadr pmid)) (cadr u)))
            (- oasis:*fuzz*))
         (> (+ (* (- (car q2) (car pmid)) (car u))
               (* (- (cadr q2) (cadr pmid)) (cadr u)))
            (- oasis:*fuzz*)))
     "the shallow break reaches past the deep one -- the two look swapped")
    ((setq bad (oasis:offbad arcs off))
     (strcat "the " bad " bulge is not " (rtos off) " wide, so there is"
             " no hopper wall to draw inside it"))
    ((null (setq offall (oasis:offring arcs off)))
     "that offset leaves no pool inside it")
    ((oasis:crossings offall)
     "at that offset the hopper wall runs through itself")
    ((null (setq cut (oasis:hopcut offall pda u pmid u)))
     "the offset closes the deep end before it reaches the break")
    (t
     (setq ca  (car cut)
           cb  (cadr cut)
           hop (oasis:subring offall ca cb)
           cs  (car (oasis:ringat offall ca))
           ce  (car (oasis:ringat offall cb)))
     ;; the corner at the start of the hopper's walk belongs to the wall
     ;; end that walk starts from: the offset ring runs the same way
     ;; round as the wall and stays the offset inside it, so the crossing
     ;; before the deepest point is the one off pda and the crossing
     ;; after it the one off pdb
     ;; the back: the deepest point of the hopper, and the wall it is
     ;; measured off
     (setq bp    (car (oasis:reach offall ca (oasis:spanlen offall ca cb)
                                   pmid u oasis:*hopscan*))
           backh (car (oasis:ringat offall bp))
           backw (car (oasis:ringat arcs (oasis:ringnear arcs backh))))
     (list hop cs ce pda pdb qsa qsb ssa da ssb db backw backh))))

;; A LINE on one layer, optionally with a linetype of its own.
(defun oasis:mkline (p q base lay lt / lst)
  (setq lst (list '(0 . "LINE")
                  (cons 8 lay)
                  (cons 10 (trans (oasis:wp p base) 1 0))
                  (cons 11 (trans (oasis:wp q base) 1 0))))
  (if (and lt (/= lt "CONTINUOUS"))
      (setq lst (append lst (list (cons 6 lt) (cons 48 (oasis:ltsc))))))
  (entmake lst)
  (entlast))

;; An open polyline through PTS.
(defun oasis:mkpl (pts base lay / lst p)
  (setq lst (list '(0 . "LWPOLYLINE")
                  '(100 . "AcDbEntity")
                  (cons 8 lay)
                  '(100 . "AcDbPolyline")
                  (cons 90 (length pts))
                  '(70 . 0)))
  (foreach p pts
    (setq lst (append lst (list (cons 10 (trans (oasis:wp p base) 1 0))))))
  (entmake lst)
  (entlast))

;; One slope line, from a hopper corner up to the shallow break point on
;; its own side.  Straight is a clean run; guided follows the pool's own
;; wall with its offset easing from the hopper's at the deep break to
;; nothing at the shallow one, so it lands on the shallow break having
;; followed the curve in.  Either way it departs from the corner itself.
(defun oasis:slope (arcs ss sd off corner shal guided base lay / pts)
  (if (not guided)
      (oasis:mkline corner shal base lay nil)
      (progn
        (setq pts (oasis:chordrun arcs ss sd 0.0 off oasis:*hopchord*))
        ;; the walk ends at the deep break; the line has to end on the
        ;; corner, which sits on the break line itself
        (setq pts (reverse (cons corner (cdr (reverse pts))))
              pts (cons shal (cdr pts)))
        (oasis:mkpl pts base lay))))

;; Draw the whole bottom and dimension it.  Returns the entities made.
(defun oasis:drawbottom (bot arcs base w h lt ga gb off
                         / hop cs ce pda pdb qsa qsb ssa da ssb db backw
                           backh out doff sh p)
  (setq hop  (nth 0 bot)  cs   (nth 1 bot)  ce   (nth 2 bot)
        pda  (nth 3 bot)  pdb  (nth 4 bot)  qsa  (nth 5 bot)
        qsb  (nth 6 bot)  ssa  (nth 7 bot)  da   (nth 8 bot)
        ssb  (nth 9 bot)  db   (nth 10 bot) backw (nth 11 bot)
        backh (nth 12 bot)
        doff (oasis:dimoff w h)
        out  nil)
  (setvar "CLAYER" oasis:*poollayer*)
  ;; the shallow break, straight across
  (setq out (cons (oasis:mkline qsa qsb base oasis:*poollayer* nil) out))
  ;; the deep break in three collinear pieces: a dashed stub from each
  ;; wall in to its hopper corner, a solid run across the hopper between
  (setq out (cons (oasis:mkline pda cs base oasis:*poollayer* lt) out)
        out (cons (oasis:mkline cs ce base oasis:*poollayer* nil) out)
        out (cons (oasis:mkline ce pdb base oasis:*poollayer* lt) out))
  ;; the hopper itself -- arcs and runs, not facets
  (setq out (append (oasis:draw hop base oasis:*poollayer*) out))
  ;; a slope line up each side
  (setq out (cons (oasis:slope arcs ssa da off cs qsa ga base
                               oasis:*poollayer*)
                  out)
        out (cons (oasis:slope arcs ssb db off ce qsb gb base
                               oasis:*poollayer*)
                  out))
  ;; the K/L/M string: wall to hopper, hopper across, hopper to wall,
  ;; all chained on one line a stand-off clear of the deep break on the
  ;; SHALLOW side, so it reads from the shallow end rather than from
  ;; over the deep end it measures
  (setvar "CLAYER" oasis:*dimlayer*)
  (oasis:dimstyle-on oasis:*dimstyle*)
  (setq sh (cal:v* (oasis:deepdir pda pdb
                                    (list (* 0.5 (+ (car qsa) (car qsb)))
                                          (* 0.5 (+ (cadr qsa) (cadr qsb)))))
                     -1.0))
  (foreach p (list (list pda cs) (list cs ce) (list ce pdb))
    (command "_.DIMALIGNED"
             (oasis:wp (car p) base) (oasis:wp (cadr p) base)
             (oasis:wp (polar (list (* 0.5 (+ (car (car p)) (car (cadr p))))
                                    (* 0.5 (+ (cadr (car p))
                                              (cadr (cadr p)))))
                              (atan (cadr sh) (car sh))
                              doff)
                       base)))
  ;; and the offset itself, where it is squarest to the wall
  (oasis:crossdim backw backh base)
  out)

;; The hopper offset, re-asked until a hopper can be built on it.  What
;; rules one out is never the number on its own -- it is the number
;; against this pool -- so the check is the build itself.  Returns
;; (offset bottom), or OASIS-BACK.
(defun oasis:askhopoff (arcs sh sd / off bot try)
  (setq bot nil)
  (while (null bot)
    (initget 6 "Back Undo")
    (setq off (getdist (strcat "\nHopper offset in from the wall [Back] <"
                               (rtos oasis:*hopoff*) ">: ")))
    (cond
      ((and (= (type off) 'STR) (member off '("Back" "Undo")))
       (setq bot 'OASIS-BACK))
      (t
       (if (null off) (setq off oasis:*hopoff*))
       (setq try (oasis:bottom arcs (car sh) (cadr sh) (car sd) (cadr sd)
                               off))
       (if (= (type try) 'STR)
           (princ (strcat "\nAt " (rtos off) " " try "."))
           (setq oasis:*hopoff* off
                 bot            (list off try))))))
  bot)

;; How one slope line runs.  The side is named by the arc its end of the
;; deep break lands on, so there is never a doubt which of the two is
;; being asked about.  Returns T for guided, nil for straight, or
;; OASIS-BACK.
(defun oasis:askslope (arcs bot which / da nm v)
  (setq da (if (= which 0) (nth 8 bot) (nth 10 bot))
        nm (nth 0 (nth (nth 2 (oasis:ringat arcs da)) arcs))
        v  (oasis:askkw (strcat "Slope line on the " nm " side")
                        "Straight Guided" "Straight/Guided" "Straight" T))
  (if (eq v 'OASIS-BACK) v (= v "Guided")))

;; The whole bottom flow, with Back between its steps the way the pool's
;; own questions have it.  Back out of the first step and nothing is
;; added at all.  Returns the lines to report, so they land after the
;; pool's own, or nil when nothing was added.
(defun oasis:askbottom (arcs w h base lt / marks ans pos k v off bot done)
  (setq marks (oasis:tangmarks arcs w h base lt)
        ans   (list nil nil nil nil nil)
        pos   0)
  (while (and pos (< pos 5))
    (setq k pos
          v (cond ((= k 0) (oasis:askbreak "Shallow" arcs w h base))
                  ((= k 1) (oasis:askbreak "Deep" arcs w h base))
                  ((= k 2) (oasis:askhopoff arcs (nth 0 ans) (nth 1 ans)))
                  (t       (oasis:askslope arcs (cadr (nth 2 ans))
                                           (- k 3)))))
    (if (eq v 'OASIS-BACK)
        (if (> pos 0)
            (progn (princ "\nStepping back one step.")
                   (setq pos (1- pos)))
            (progn (princ "\nNo bottom added.")
                   (setq pos nil)))
        (setq ans (oasis:put ans k v)
              pos (1+ pos))))
  (setq marks (oasis:pv-clear marks))
  (if (null pos)
      nil
      (progn
        (setq off  (car (nth 2 ans))
              bot  (cadr (nth 2 ans))
              done (oasis:drawbottom bot arcs base w h lt
                                     (nth 3 ans) (nth 4 ans) off))
        (list
          (strcat "\nBottom on layer " oasis:*poollayer*
                  ": the shallow break, the three-piece deep break"
                  " (dashed stubs,")
          (strcat "\n  solid middle), the hopper " (rtos off)
                  " in from the wall, and the slope lines ("
                  (if (nth 3 ans) "guided" "straight") " / "
                  (if (nth 4 ans) "guided" "straight") ").")
          (strcat "\n  K/L/M at the deep break: "
                  (rtos (distance (nth 3 bot) (nth 1 bot))) " / "
                  (rtos (distance (nth 1 bot) (nth 2 bot))) " / "
                  (rtos (distance (nth 2 bot) (nth 4 bot))) ".")))))

;;; -------------------- reporting ---------------------------------------

;; The bulges the ring left out.  A bulge whose two joiners hand over at
;; the same point is a point on the outline rather than an arc of it, and
;; oasis:solve drops it -- so the radius the user gave for it is not in
;; the drawing anywhere, which is worth saying out loud.  Bulges sit at
;; the even positions of the name list.
(defun oasis:pinched (arcs variant / have nm out i)
  (setq have (mapcar 'car arcs)
        nm   (oasis:names variant)
        out  nil
        i    0)
  (while (< i (length nm))
    (if (and (= 0 (rem i 2)) (not (member (nth i nm) have)))
        (setq out (cons (nth i nm) out)))
    (setq i (+ i 1)))
  (reverse out))


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
  (setq bad (oasis:overlaps arcs))
  (if bad
      (progn
        (princ "\nOASIS: the outline runs over the same circle twice --")
        (foreach p bad
          (princ (strcat "\n         the " (car p) " arc laps the "
                         (cadr p) " arc")))
        (princ "\n       The lobe they are both cut from is handed over in")
        (princ "\n       the wrong order.  One U takes it away; the tangent")
        (princ "\n       radii round that lobe are what decide it."))
  )
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
                   rl rt rr ftl ftr fbc fbr off cbase arcs ents nests prev
                   lt a nchk gotbot)
  (defun *error* (msg)
    ;; user settings come back FIRST so nothing below can skip them
    (cal:dimstyrestore)
    (cal:sysrestore)
    ;; a form's leftovers go with the run that was reading them: an Esc
    ;; part-way through must not leave answers behind for the next one
    (oasis:fclear)
    (setq oasis:*fkey* nil)
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
     (setq ans '(nil nil nil nil nil nil nil nil nil nil nil nil nil nil)
           pos 0)
     (while (progn (setq steps (oasis:steps ans))
                   (< pos (length steps)))
       (setq k    (nth pos steps)
             prev (oasis:preview prev ans k)
             v    (oasis:askstep k ans))
       (if (eq v 'OASIS-BACK)
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
                   ((oasis:nxt-p (oasis:variant ans))
                    (setq nests (oasis:nxt-nests (nth 2 ans) (nth 3 ans)
                                                 (nth 4 ans) (nth 5 ans)
                                                 (nth 6 ans)))
                    (if nests
                        (progn
                          (princ (strcat "\nThat right lobe and the " nests
                                         " lobe lie one inside the other, so"
                                         " no tangent radius can join them."
                                         "  Asking again."))
                          (setq pos (1- pos)))))
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
                                                   (nth 6 ans) (nth 12 ans)
                                                   (oasis:variant ans)))
                    (if nests
                        (progn
                          (princ (strcat "\nThat right bulge and the " nests
                                         " bulge lie one inside the other, so no"
                                         " tangent radius can join them.  Asking"
                                         " again."))
                          (setq pos (1- pos))))))))))

     ;; the questions are over: nothing after this point is a form's to
     ;; answer, the pool-bottom flow at the end least of all
     (setq oasis:*fkey* nil)
     (setq prev (oasis:pv-clear prev)
           var  (oasis:variant ans) base (nth 1 ans)
           w    (nth 2 ans) h    (nth 3 ans)
           rl   (oasis:leftrad var (nth 3 ans) (nth 4 ans))
           rt   (nth 5 ans) rr (nth 6 ans)
           ftl  (nth 7 ans) ftr  (nth 8 ans) fbc (nth 9 ans)
           fbr  (nth 13 ans) off (nth 12 ans)
           arcs (oasis:solve w h rl rt rr ftl ftr fbc fbr off var))

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

           (princ (strcat "\nOASIS " *oasis-version* ": " (rtos w) " x "
                          (rtos h) " " (oasis:vlabel var)
                          (if (oasis:complex-p ans) " complex" "")
                          " oasis on layer " oasis:*poollayer* "."))
           (if (and off (/= off 0.0))
               (princ (strcat "\n  hump " (rtos (abs off)) " off centre to the "
                              (if (< off 0.0) "left" "right") ".")))
           (foreach a arcs
             (princ (strcat "\n  " (cal:pad (nth 0 a) 14)
                            (if (oasis:line-p a)
                                (strcat "straight run, "
                                        (rtos (distance (nth 1 a) (nth 2 a))))
                                (strcat (cond ((not (nth 5 a)) "reverse R")
                                              ((oasis:nxt-p var) "lobe   R")
                                              ("bulge  R"))
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
           (foreach a (oasis:pinched arcs var)
             (princ (strcat "\nOASIS: the " a " bulge is pinched out -- the"
                            " two joiners either side of it"))
             (princ (strcat "\n       touch it at the same point, so it is a"
                            " point on the outline and"))
             (princ "\n       nothing is drawn for it."))
           (oasis:report-extents arcs w h)
           (oasis:report-crossings arcs)

           ;; and then, if it is wanted, the floor -- laid out on the
           ;; outline that has just been built, so every point of it can
           ;; be said exactly instead of picked at.  Still inside the
           ;; undo group: one U takes the pool and its bottom together.
           (cal:osup)
           (if (= "Yes" (oasis:askkw
                          "Add the bottom of the pool (breaks and hopper)?"
                          "Yes No" "Yes/No" "No" nil))
               (setq gotbot (oasis:askbottom arcs w h base lt)))
           (cal:osdown)
           (cal:dimstyrestore)

           (command "_.UNDO" "_End")
           (setq undo-open nil)
           (cal:sysrestore)
           (foreach a gotbot (princ a))))))
  ;; whatever route the run took out, the store goes with it -- an
  ;; answer nothing asked for must not be waiting for the next run
  (oasis:fclear)
  (setq oasis:*fkey* nil)
  (princ))

(defun c:OASISVER ()
  (princ (strcat "\nOASIS " *oasis-version*))
  (princ))

(princ (strcat "\nOASIS " *oasis-version*
               " loaded.  Type OASIS to draw a continuous-tangent pool."))
(princ)
