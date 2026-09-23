;;; ======================================================================
;;; CONSTELLATION.lsp  --  points placed from the dims between them
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  CONSTELLATION     place labelled points from their cross dims
;;;            CONSTELLATIONVER  print the loaded version
;;;
;;; The job this exists for: a site sheet that gives distances BETWEEN
;;; points and never says where any of them is.  A tape run corner to
;;; corner, corner to skimmer, skimmer to light -- fourteen numbers and
;;; no origin.  Every other calofin importer wants coordinates (XYPLOT
;;; is handed X and Y; ABCDEF is handed offsets off a baseline).  This
;;; one is handed only the web of distances and has to work the
;;; positions out.
;;;
;;; THE RUN, in order:
;;;
;;;   1. THE SPACE.  A rectangle of known X and Y that the points are
;;;      allowed to sit in -- the yard, the deck, the envelope the pool
;;;      has to land inside.  It is asked first because it is also what
;;;      sets the SCALE of the first guess: without it the solver has no
;;;      idea whether this is a 12 foot spa or a 60 foot pool.
;;;
;;;   2. HOW MANY POINTS, labelled A, B, C ... up to Z.
;;;
;;;   3. THE STARTING LAYOUT, drawn on screen before a single dim is
;;;      asked for: the points evenly spaced round the oval inscribed in
;;;      the space, running CLOCKWISE FROM THE TOP LEFT.  Nothing about
;;;      it is a measurement - it is there so the operator can see which
;;;      letter is which before naming a pair.  It is erased again the
;;;      moment the real positions are known.
;;;
;;;   4. THE CROSS DIMS.  Every pair -- A-B, A-C, A-D ... -- is on
;;;      offer and NONE is compulsory.  A field sheet almost never
;;;      carries all of them; the point is to let the operator enter
;;;      the ones it does carry, in whatever order they are written
;;;      down.  What IS required is two dims on every point, because a
;;;      point with one dim sits anywhere on a circle and a point with
;;;      none sits anywhere at all.
;;;
;;;   5. THE ARCS.  A run of points that lies on ONE radius, named
;;;      CLOCKWISE -- A-C, or ABC spelled out, or the wrap Z-B meaning
;;;      Z A B.  Cross dims say how far apart things are and nothing
;;;      about how the wall between them curves, so a radius end can be
;;;      measured perfectly and still come out as a flat chord.  To the
;;;      solver an arc is simply one more point, its centre, a dim of R
;;;      away from every point on it -- and it pins what the dims leave
;;;      loose.
;;;
;;;   6. THE SOLVE, then the drawing: an ab_pt survey point per letter,
;;;      an aligned dimension per dim given, the space itself, and an
;;;      outline that bends round any arc declared.
;;;
;;;   7. DOES IT LOOK RIGHT?  A number typed wrong is the ordinary case,
;;;      not an exception: nobody can tell 24'-6" was meant to be 24'-9"
;;;      from the chart, and anybody can tell from the drawing.  So the
;;;      drawing is the check.  A No asks whether the dims, the arcs or
;;;      both need changing, takes the corrected value, takes the wrong
;;;      drawing away and puts the right one down, round as many times
;;;      as it takes.
;;;
;;; WHAT THE SOLVER DOES.  The dims are almost never exactly consistent
;;; -- a tape reads a sixteenth long, a corner is measured to the
;;; coping instead of the wall -- so there is usually NO layout that
;;; satisfies all of them.  What is computed is the layout that misses
;;; by as little as possible, and the report says how far each dim
;;; ended up from what was given.  A dim that will not come into line
;;; is a dim to go back and re-measure, which is the most useful thing
;;; this command can tell anyone -- and it is only worth saying if the
;;; fit is exact when the dims ARE consistent, which is why the solve
;;; runs in two stages: sweeps to find the right answer, then damped
;;; Gauss-Newton to land on it exactly.  See both stages below.
;;;
;;; TWO THINGS THE DISTANCES CANNOT SETTLE, and how they are settled:
;;;
;;;   WHICH WAY ROUND.  A constellation and its mirror image satisfy
;;;     exactly the same distances.  The operator was shown A, B, C
;;;     running clockwise, so the mirror that reads clockwise is drawn.
;;;
;;;   WHICH WAY UP.  Distances are rotation-blind too, so the result is
;;;     turned to sit inside the space -- and among the angles that fit,
;;;     to land as near as it can to the oval that was previewed, so the
;;;     letters stay roughly where they were shown.
;;;
;;; All geometry is created in inches (1 drawing unit = 1 inch).
;;; ======================================================================

(vl-load-com)

;; Version banner, shown on load and at the top of every run's report.
(setq *constellation-version* "v1.9")

;;; -------------------- tunables ----------------------------------------
;;
;; Everything a drafter might reasonably want different is set HERE and
;; nowhere else: the code below reads these names and carries no bare
;; numbers of its own.  Each knob says what CHANGING it does.  Change a
;; value, save, APPLOAD again - or (setq cst:*name* value) at the
;; command line for one session.  Every one of them is a row in
;; README.md's Tunables table, and tests/test_tunables.py holds the two
;; together.
;;
;; Distances are in inches throughout (1 drawing unit = 1 inch).
;;
;; The groups run in the order the command meets them: what it draws
;; on, the survey block, how many points, a prompt default, the solve,
;; the turn-to-fit, the report, the drawing sizes.

;; ---- where the result goes -----------------------------------------------

;; The layer each part of the result lands on.  Point one at a layer
;; the office already uses and the result joins that layer's work;
;; point it somewhere new and it stands apart, ready to freeze on its
;; own.
(setq cst:*space-layer*   "CONSTELLATION-SPACE")   ; the rectangle asked for
(setq cst:*guide-layer*   "CONSTELLATION-GUIDE")   ; the starting oval, erased
(setq cst:*outline-layer* "CONSTELLATION")         ; the ring through A B C ...
(setq cst:*dim-layer*     "DIMENSION")             ; as AUTODIM and WCALST
(setq cst:*point-layer*   "POINTS")                ; as ABCDEF and XYPLOT

;; The ACI colour each of those layers is CREATED with.  Moving one
;; changes nothing in a drawing that already has the layer -- an
;; existing layer keeps its own colour and is only switched on, thawed
;; and unlocked if it needs to be, so the result is never drawn where
;; nobody can see it.  1 red, 2 yellow, 3 green, 4 cyan, 5 blue,
;; 6 magenta, 7 white, 8 grey.  Grey for the frame and cyan for the
;; legend, so neither competes with the result; the result itself lands
;; in the point and dimension colours the rest of the toolkit uses.
(setq cst:*space-color*   8)      ; grey.  The space rectangle is part
                                  ; of the output and its layer outlives
                                  ; the command, so a NUMBER, never
                                  ; 'auto: one colour for everyone who
                                  ; opens the file, not one drafter's
                                  ; theme.  LAZTUNE can still change it
(setq cst:*guide-color*   4)
(setq cst:*outline-color* 3)
(setq cst:*dim-color*     2)
(setq cst:*point-color*   2)

;; ---- the survey block ----------------------------------------------------

;; ABCDEF's survey block and its attribute tag.  Move either and ABHD,
;; CABHD, ABFIND, LHD and BPCALLOUT stop recognising what this command
;; imports, so they only ever move together with ABCDEF and XYPLOT.
(setq cst:*point-block* "ab_pt")
(setq cst:*point-tag*   "number")

;; ---- how many points -----------------------------------------------------

;; The labels, in the order they are handed out clockwise.  Shortening
;; the string lowers the ceiling below with it; anything else about it
;; renames the points.
(setq cst:*letters*  "ABCDEFGHIJKLMNOPQRSTUVWXYZ")

;; The count the run will accept.  Raising the floor refuses small jobs
;; the solver can do; the ceiling is read off the label string at load,
;; so a shorter alphabet set afterwards has to set this with it or
;; cst:letter is asked for a letter that is not there.
(setq cst:*minpts*   3)
(setq cst:*maxpts*   (strlen cst:*letters*))

;; What Enter takes at the count prompt.  Set it to the job you do most
;; and the common case becomes one keystroke; it is clamped into the
;; range above at the ask, so a value outside it costs nothing.
(setq cst:*defcount* 4)

;; ---- a prompt default ----------------------------------------------------

;; What Enter takes at "Draw the outline through the points in order?"
;; -- "No" to make the ring something asked for rather than assumed
;; (anything but "No" reads as "Yes").  The run's other defaults are
;; deliberately not knobs: the base point defaults to the origin because
;; that is AutoCAD's own convention, and "does it look right" defaults
;; to Yes because a run that went well is the common one.
(setq cst:*def-outline* "Yes")

;; ---- the solve, stage 1: sweeps ------------------------------------------

;; Stress-majorization sweeps only have to get the layout into the
;; right BASIN, which takes a few dozen; stage 2 finishes the fit.
;; Raising the cap costs time on every start and buys almost nothing.
(setq cst:*sweeps* 120)

;; How far the furthest point moved in one sweep, in drawing units,
;; below which sweeping stops early.  Lowering it sweeps longer for a
;; start stage 2 would have reached anyway.
(setq cst:*tol*    1.0e-6)

;; ---- the solve, stage 2: Levenberg-Marquardt -----------------------------

;; The outer steps, and the damping retries allowed inside one of them
;; before the fit is called finished.  Lowering either stops the fit
;; short of the answer, which shows up as misses the report then blames
;; a tape for.
(setq cst:*lm-iters*  40)
(setq cst:*lm-tries*   8)

;; The damping itself: what it starts at, the floor it may fall to, and
;; what a step that reduced the miss and a step that did not multiply
;; it by.  These four are the fit's temperament rather than settings to
;; reach for -- move them and a chart that used to land exactly may
;; stop.
(setq cst:*lm-lam*    1.0e-3)
(setq cst:*lm-lammin* 1.0e-12)
(setq cst:*lm-down*   0.1)
(setq cst:*lm-up*     10.0)

;; The sum of squared misses below which there is nothing left to gain
;; -- about a ten-millionth of an inch, RMS.  The one stage-2 knob
;; worth reaching for, and only to LOOSEN it on a machine where a
;; 26-point job is too slow.
(setq cst:*lm-done*   1.0e-14)

;; ---- the starts tried ----------------------------------------------------

;; A stress minimum is LOCAL, and a constellation that starts folded
;; can stay folded, so the oval is not the only start tried: raise
;; either and the second and third starts fall further from it, which
;; finds a folded shape more often and moves nothing on a chart that
;; was already landing.  *squash* flattens the oval to this share of
;; its height; *shake* scatters it by this share of the smaller space
;; dimension.
(setq cst:*squash* 0.35)
(setq cst:*shake*  0.30)

;; ---- turn-to-fit ---------------------------------------------------------

;; The solved shape is spun to sit in the space: the whole circle
;; sampled *rot-coarse* ways, then *rot-passes* refining passes of
;; *rot-fine* samples, each one grid spacing either side of the last
;; winner.  Lowering any of them can miss the window a long thin
;; constellation in a tight space fits through, which is sometimes only
;; a fraction of a degree wide.
(setq cst:*rot-coarse* 360)
(setq cst:*rot-fine*   40)
(setq cst:*rot-passes* 3)

;; ---- the report ----------------------------------------------------------

;; How far a dim or an arc radius may end up from what was given before
;; it is starred and the leave-one-out test goes looking for the tape
;; to blame.  Drawing units: at a sixteenth of an inch nobody
;; re-measures, at a quarter something is wrong with the sheet.  Raise
;; it and a bad tape stops being reported.
(setq cst:*flag*     0.25)

;; How far the points may reach past the space, the two axes added,
;; before the report says so.  Raise it to stop hearing about overhang
;; nobody can see.
(setq cst:*over-tol* 1.0e-6)

;; ---- drawing sizes -------------------------------------------------------

;; Label height, preview marker radius and how far a perimeter dim
;; stands off, as shares of the smaller side of the space -- so a spa
;; and a pool both come out in proportion.  Raise one and that part of
;; the drawing grows with the job.
(setq cst:*texth*     0.025)
(setq cst:*dotr*      0.008)
(setq cst:*dimoff*    0.060)

;; Floors under the first two, in drawing units, so a tiny space still
;; gets a label that can be read and a marker that can be seen.  Raise
;; one and small jobs get bigger text or fatter markers.
(setq cst:*texth-min* 0.5)
(setq cst:*dotr-min*  0.1)

;; The LENGTH RULER beside the ARC RADIUS prompt.  When a run of points
;; lies on one radius the operator is asked what that radius is, and a
;; wall's radius comes off a plan in whole feet rather than being taped
;; off anything -- so the prompt stands beside DIMSTAMP's ruler, drawn
;; down a strip near the right edge of the view, and a click on a row
;; IS the radius.  Scratch on its own layer, taken down before any
;; prompt that does not take it and on every way out.  Every size is a
;; fraction of the current view, so the ruler reads the same at any
;; zoom.  The two SPACE bounds beside it are measured off a site plan
;; and stay the plain typed questions they were.
(setq cst:*ruler-layer* "CONSTELLATION-RULER") ; scratch layer the rows
                                               ; are drawn on
(setq cst:*ruler-color* 3)         ; ACI colour of the rows you can PICK
(setq cst:*ruler-current-color* 7) ; ACI colour of the ringed CURRENT
                                   ; row; 7 is AutoCAD's black/white
                                   ; swap
(setq cst:*ruler-screen-x* 0.88)   ; where the spine sits across the
                                   ; view, as a fraction of its width in
                                   ; from the left; past 0.5 the rows
                                   ; reach left, short of it they reach
                                   ; right, so the ruler is always
                                   ; inside the view
(setq cst:*ruler-row-frac* 0.042)  ; one row's share of the view's
                                   ; height -- the ruler's size knob
(setq cst:*ruler-txt-frac* 0.5)    ; the biggest row label's height, as
                                   ; a fraction of the row spacing
(setq cst:*ruler-tick-frac* 0.6)   ; the longest tick, same measure
(setq cst:*ruler-ring-frac* 0.26)  ; the ring round the current row, as
                                   ; a fraction of the row spacing
(setq cst:*ruler-reach* 6.0)       ; how far inboard of the spine, in
                                   ; row spacings, a click still counts
                                   ; as picking a row rather than as the
                                   ; first point of a measured length

;; The LADDER it stands on, as (LOW HIGH STEP) in inches: the radii a
;; curved wall is drawn to, 2' to 20' by a foot.  A shop whose walls
;; run to some other measure sets its own; nil leaves the prompt the
;; plain typed one it was.
(setq cst:*radius-ladder* '(24.0 240.0 12.0))

;;; ----------------------------------------------------------------------
;;;  Constants that are NOT knobs
;;;
;;;  The length ruler's STATE, first: a RUN state, not a setting -- it
;;;  is what the run put there, and editing it here changes nothing.
;;;  A module global rather than a local of cst:askarcs, because the
;;;  reader is several calls down from c:CONSTELLATION and what that
;;;  command's *error* can take down is what the command can see: Esc
;;;  at a radius is the likeliest way out of the question, and a ruler
;;;  left standing is scratch in somebody's drawing.
(setq cst:*ruler* nil)
;;;
;;;  And, for the reader who comes here looking: the other numbers
;;;  further down that look tunable and are left where they are, each
;;;  tied to something that would have to move with it.
;;;
;;;    WHERE A SITS AND WHICH WAY THE LETTERS RUN (cst:oval: 135
;;;      degrees, stepping clockwise).  Top left, clockwise, is the
;;;      order a pool's corners are called out in; the preview's
;;;      message, the arc help, the wrap rule Z-B = Z A B, the mirror
;;;      test and the bow question all assume it.
;;;    THE ab_pt GEOMETRY (cst:ensure-block, cst:insert-pt).  ABCDEF's
;;;      definition, repeated so a drawing can hold both imports.
;;;    THE FLOATING-POINT GUARDS (1e-9 and 1e-12 in the solver).  Where
;;;      two points count as coincident, or a pivot as zero; they keep
;;;      divisions finite and carry no measurement meaning.
;;;    THE LIBRARY HELPERS (the Ask, Settings and Vector sections
;;;      below).  Their bodies are CALOFIN-LIB's byte for byte, and the
;;;      grouped build swaps them for the library's own -- a change
;;;      made here would be lost there.
;;; ----------------------------------------------------------------------

;; NOT A KNOB: the golden angle, in radians.  It is what makes the
;; scattered start and the coincident-point push-apart spread evenly
;; without a random number generator, so the same job drawn twice comes
;; out the same.  Any other value clumps them.  Named once because two
;; places need it and they must not disagree.
(setq cst:*golden* 2.399963229728653)

;;; ----------------------------------------------------------------------
;;;  Ask layer  --  the STANDARDS section 4 helpers
;;;
;;;  Copies of CALOFIN-LIB.lsp's cal: originals under this file's own
;;;  prefix, so it loads alone with APPLOAD; in the shared/ twin they
;;;  are gone and every call site reads cal: instead (STANDARDS section
;;;  6).  Bodies identical to the library's.
;;;
;;;  askkw takes the bracket text SHOWN third, like the library's.  The
;;;  only keyword question this tool asks is the Yes/No at the end, so
;;;  askkw is here for askyn to call and has no other call site whose
;;;  bracket could drift from its keywords.  Back is signalled by the
;;;  sentinel symbol these helpers return, which the twin renames along
;;;  with them -- so every call site tests for it by name and neither
;;;  tier needs a special case.
;;; ----------------------------------------------------------------------

;; A per-ROLE colour override: CalofinInk-<ROLE> in the profile, or nil
;; when none is set -- or when what is set is not a colour (1-255), as an
;; older CALSET could store.  CALOFIN-LIB.lsp's cal:inkoverride is this
;; function; the copy is here because a standalone file has to load alone.
(defun cst:inkoverride (role / q v)
  (setq q (assoc role '((fade . "FADE") (guide . "GUIDE") (dim . "DIM")
                         (hi . "HI") (flag . "FLAG") (arc . "ARC")
                         (olap . "OLAP") (orig . "ORIG") (sugg . "SUGG")
                         (point . "POINT") (constr . "CONSTR")
                         (report . "REPORT"))))
  (if q
    (progn
      (setq v (getenv (strcat "CalofinInk-" (cdr q))))
      (if (and v (/= v "")) (setq v (atoi v)))
      (if (and (numberp v) (< 0 v 256)) v))))

;;  A colour knob set to 'auto asks for the ACI that suits the
;;  background it will be seen against; a knob set to a NUMBER is used
;;  exactly as given, so a shop that has picked its own colours keeps
;;  them and so does a test that sets one.
;;
;;    role     what it is                    dark  light  unmeasured
;;    fade     a review tool's grey-out       251    254        8
;;    guide    preview and guide geometry     253      8        8
;;    dim      a chart tile's dimensions      253      8        8
;;    hi       a chart tile's active box        4      5        5
;;
;;  fade and guide are drawn into the DRAWING, so they measure its
;;  background; dim and hi are drawn inside a dialog, where -15 and -16
;;  already follow AutoCAD's interface theme, so they follow that
;;  instead.  The two are different questions: a light-themed AutoCAD
;;  over the stock near-black model space is an ordinary way to work.
;;  CalofinTheme in the profile overrides both -- CALSET writes it --
;;  and the unmeasured column is what this tool drew before the table
;;  existed, so a session that cannot tell is not a session that
;;  behaves differently.
;;
;;  Nothing is cached: the call sites that run in a loop resolve once
;;  into a local before the loop, which is where the volume is.
;;  CALOFIN-LIB.lsp's cal:ink is this function; the copy is here
;;  because a standalone file has to load alone.
(defun cst:ink (knob role / v th c lum)
  ;; numberp, not (eq knob 'auto): a knob is a colour NUMBER used
  ;; exactly as given, or it is resolved.  Testing for 'auto instead
  ;; would hand back whatever a mistyped knob holds -- nil, or the
  ;; symbol AUOT -- and that reaches entmake as a DXF group 62, where
  ;; it dies a long way from the line that caused it.
  (cond
    ((numberp knob) knob)
    ;; a CalofinInk-<ROLE> override in the profile (CALSET, LAZBACKUP)
    ;; beats the table, as it does in cal:ink -- without this clause the
    ;; grouped build honoured one and this file, loaded alone, did not
    ((cst:inkoverride role))
    (t
      ;; trimmed: this is typed by a person, and " dark " meaning
      ;; nothing at all would be a silent no-op to stare at
      (setq v  (getenv "CalofinTheme")
            v  (if (and v (/= v "")) (strcase (vl-string-trim " \t" v))
                   "AUTO")
            th (cond
                 ((= v "DARK") 'dark)
                 ((= v "LIGHT") 'light)
                 ((member role '(dim hi))
                  (cond ((null (setq c (getvar "COLORTHEME"))) nil)
                        ((= c 0) 'dark)
                        (t 'light)))
                 (t
                  (setq c (vl-catch-all-apply
                            '(lambda ()
                               (vl-load-com)
                               (vla-get-GraphicsWinModelBackgrndColor
                                 (vla-get-Display
                                   (vla-get-Preferences
                                     (vlax-get-acad-object)))))
                            nil))
                  (if (or (vl-catch-all-error-p c) (not (numberp c)))
                    nil
                    (progn
                      ;; an OLE colour is packed low byte first: R, G, B
                      (setq c   (fix c)
                            lum (+ (* 0.30 (rem c 256))
                                   (* 0.59 (rem (/ c 256) 256))
                                   (* 0.11 (rem (/ c 65536) 256))))
                      (if (< lum 128.0) 'dark 'light))))))
      (cond
        ((eq role 'fade)
         (cond ((eq th 'dark) 251) ((eq th 'light) 254) (t 8)))
        ((eq role 'guide)
         (cond ((eq th 'dark) 253) ((eq th 'light) 8) (t 8)))
        ((eq role 'dim)
         (cond ((eq th 'dark) 253) ((eq th 'light) 8) (t 8)))
        ((eq role 'hi)
         (cond ((eq th 'dark) 4) ((eq th 'light) 5) (t 5)))
        (t 7)))))

(defun cst:askkw (msg kws shown dflt back / v)
  (initget (if dflt 0 (if back 0 1))
           (if back (strcat kws " Back Undo") kws))
  (setq v (getkword (strcat "\n" msg " [" shown
                            (if back "/Back" "") "]"
                            (if dflt (strcat " <" dflt ">") "") ": ")))
  (if lzd:ask (lzd:ask msg v) v)
  (cond ((member v '("Back" "Undo")) 'CST-BACK)
        ((null v) (if dflt dflt (cst:askkw msg kws shown dflt back)))
        (t v)))

;; Yes/No that can be backed out of.  Returns T, nil or CST-BACK.
(defun cst:askyn (msg dflt back / v)
  (setq v (cst:askkw msg "Yes No" "Yes/No" dflt back))
  (if (eq v 'CST-BACK) v (= v "Yes")))

;; Distance entry with the kind system of STANDARDS.md section 3:
;; REQ required, NAX accepts NA, ZER accepts NA and zero, SUG offers a
;; default that Enter takes.  Returns the number, nil for NA, or
;; CST-BACK.
;; LADDER nil is the plain typed question this has always been; a
;; (LOW HIGH STEP) stands it beside the LENGTH RULER, which is what the
;; ARC RADIUS hands in and neither space bound does -- a bound is
;; measured off a site plan, and there is no short list of what one
;; comes to.
(defun cst:askdist (kind msg dflt back ladder / v kw rr prompt)
  ;; Undo is accepted everywhere Back is, as a hidden synonym
  (setq kw (cond ((eq kind 'REQ) (if back "Back Undo" nil))
                 (back "NA Back Undo")
                 (t "NA")))
  ;; the prompt's TEXT is built once, above the fork, so the two routes
  ;; in cannot drift apart
  (setq prompt (strcat "\n" msg
                       (cond ((eq kind 'REQ) "")
                             ((eq kind 'SUG)
                              (if dflt (strcat " <" (rtos dflt) "> (or NA)")
                                  " (or NA)"))
                             (t " (or NA if not measured)"))
                       (if back " [Back]" "")
                       ": "))
  ;; A ZER question admits a zero and the ruler's prompt does not -- no
  ;; length on a ruler is zero -- so a ladder handed to one is ignored
  ;; rather than quietly tightening what the question takes.  Only the
  ;; radius hands one in, and it is REQ.
  (if (and ladder (not (eq kind 'ZER)))
    (progn
      (setq v nil)
      (while (null v)
        ;; the ruler goes up BEFORE the prompt and its state is the
        ;; run's, not a local: an Esc in here runs c:CONSTELLATION's
        ;; *error*, and what that can take down is what it can see
        (setq cst:*ruler*
                (cst:ruler-show (if cst:*ruler* cst:*ruler*
                                    (cst:ruler-new (cst:rulerlayer)
                                                   (cst:ruler-style)))
                                nil ladder)
              rr (cst:ask-len prompt kw cst:*ruler* nil)
              v  (car rr)
              cst:*ruler* (cadr rr))
        ;; Enter: taken as the suggestion where initget 6 took it, and
        ;; refused where 7 refused it
        (cond
          ((and (null v) (eq kind 'SUG) dflt) (setq v dflt))
          ((null v)
           (princ (strcat "\n  A radius is required - type it, or click"
                          " a ruler row.")))))
      ;; down before the answer is used: the question after a radius
      ;; asks for a ruler of its own if it wants one
      (cst:rulerkill))
    (progn
      ;; REQ always rejects zero - offering Back must not loosen what
      ;; counts as a valid measurement; ZER alone admits 0
      (if kw
          (initget (cond ((eq kind 'ZER) 5)
                         ((and (eq kind 'SUG) dflt) 6)
                         (t 7))
                   kw)
          (initget 7))
      (setq v (getdist prompt))
      (if lzd:ask (lzd:ask msg v) v)))
  (cond ((and (= (type v) 'STR) (member v '("Back" "Undo"))) 'CST-BACK)
        ((= (type v) 'STR) nil)               ; NA
        ((and (null v) (eq kind 'SUG)) dflt)  ; Enter took the suggestion
        (t v)))

;;; -------------------- the length ruler --------------------------------
;;;  DIMSTAMP's ruler, as a helper any LENGTH prompt can stand beside.
;;;  Once a first length has been given, the prompt draws the eighths
;;;  of an inch for a whole inch either side of the last one down a
;;;  strip near the right edge of the view, graded like a tape with the
;;;  last length ringed in the middle -- and one prompt then takes a
;;;  click on a row (that row's value), a typed measurement in any
;;;  spelling (44, 44.5, 44-1/2, 4'4.5, 4'-4-1/2"), Enter, a keyword,
;;;  or a click on empty space as the first of two points to measure
;;;  between, which is what getdist always offered.  A run of
;;;  near-equal lengths is clicked rather than typed over and over.
;;;  The fractions are DASHED because the prompt is a getpoint, where
;;;  the spacebar is Enter: 44 1/2 is two answers there, 44 to this
;;;  question and 1/2 to the next, so a bare fraction is refused
;;;  rather than taken as a length of its own.
;;;
;;;  PERPPTS, CPERPPTS, PERPMARK, CORNERSTP, HEMISTEP and NORMIESTEP
;;;  ask their lengths through it.  Each carries this block under its
;;;  own prefix so the standalone file loads alone, the grouped build
;;;  swaps the copy for the library's, and tests/test_ruler_copies.py
;;;  holds every copy to this one text.  DIMSTAMP keeps its own ruler:
;;;  its current row is drawn as the stamp it would make, on the
;;;  stamp's layer in the stamp's style, which is a different thing
;;;  from a row of nearby lengths.
;;;
;;;  A ruler comes in two families, and the prompt picks which.
;;;
;;;  The TAPE is the one above: the eighths of an inch for a whole inch
;;;  either side of the LAST answer, which is what a run of near-equal
;;;  numbers wants.  It needs a last answer to be built round, so the
;;;  first prompt of a run stands alone.
;;;
;;;  The LADDER is the other: a fixed (LO HI STEP) of the values that
;;;  prompt is actually answered with, every one of them offered from
;;;  the first prompt on.  A corner radius is 3" to 2'-0" by 3" and a
;;;  tape of eighths round nothing helps nobody -- 3, 6, 9, 12 is the
;;;  whole vocabulary, and a drafter picks out of it rather than types
;;;  into it.  Its rows are graded off the VALUE, not off a distance
;;;  from the current row: the foot marks are the deep ones and the
;;;  half-foot next, which is where a tape's deep marks are too.  A
;;;  ladder still takes a typed measurement that is not on it, and the
;;;  answer is then ringed among the rungs as the current row.
;;;
;;;  Nothing in here reads a knob.  A tool hands its knobs in as one
;;;  STYLE list and keeps the ruler between prompts as one STATE list:
;;;    STYLE  (COLOR CURRENT-COLOR SCREEN-X ROW-FRAC TXT-FRAC TICK-FRAC
;;;            RING-FRAC REACH) -- a caller's tunables block says what
;;;            each one moves
;;;    STATE  (LEN FEET ENTS BOX ROWS LAY STYLE SAID LADDER) -- the
;;;            length the ruler stands round (nil = none), the family it
;;;            is labelled in (T = feet), what is drawn, its layer, the
;;;            style, whether the one-line hint has been said, and the
;;;            ladder it is standing on (nil = a tape)
;;;  Values are INCHES, the unit this shop draws in, and the ruler
;;;  steps in eighths of one, which is what a tape reads in.

;; T when C is 0-9.
(defun cst:len-digit-p (c)
  (and (>= (ascii c) 48) (<= (ascii c) 57)))

;; T when S reads as a plain decimal number: digits, at most one dot,
;; at least one digit, nothing else.
(defun cst:len-num-p (s / i n c dots digits ok)
  (setq n (strlen s) i 1 dots 0 digits 0 ok T)
  (while (and ok (<= i n))
    (setq c (substr s i 1))
    (cond
      ((cst:len-digit-p c) (setq digits (1+ digits)))
      ((= c ".") (setq dots (1+ dots)))
      (T (setq ok nil)))
    (setq i (1+ i)))
  (and ok (> digits 0) (< dots 2)))

;; S cut on spaces, tabs and dashes, empty pieces dropped -- the
;; separators an inches part is written with, so "4 1/2" and "4-1/2"
;; come apart the same way.  It cuts a keyword list the same way.
(defun cst:len-split (s / i n c buf out)
  (setq n (strlen s) i 1 buf "" out nil)
  (while (<= i n)
    (setq c (substr s i 1))
    (if (or (= c " ") (= c "\t") (= c "-"))
      (progn
        (if (/= buf "") (setq out (cons buf out)))
        (setq buf ""))
      (setq buf (strcat buf c)))
    (setq i (1+ i)))
  (if (/= buf "") (setq out (cons buf out)))
  (reverse out))

;; One token of an inches part -- a decimal number, or a fraction N/D
;; -- as a number of inches.  nil when it is neither.
(defun cst:len-token (tok / slash n d)
  (if (setq slash (vl-string-search "/" tok))
    (progn
      (setq n (substr tok 1 slash)
            d (substr tok (+ slash 2)))
      (if (and (cst:len-num-p n) (cst:len-num-p d) (/= (atof d) 0.0))
        (/ (atof n) (atof d))))
    (if (cst:len-num-p tok) (atof tok))))

;; The inches part of a measurement as a number of inches: every token
;; added up, so "4", "4.5", "4 1/2", "4-1/2" and "1/2" all read.  An
;; empty part is 0, which is how 4' reads as 4'-0".  nil when any
;; token is neither a number nor a fraction.
(defun cst:len-inches (s / toks total v tk)
  (setq toks (cst:len-split s) total 0.0)
  (foreach tk toks
    (if (and total (setq v (cst:len-token tk)))
      (setq total (+ total v))
      (setq total nil)))
  total)

;; Read a typed measurement as (INCHES HASFEET): the length in inches,
;; exactly as typed and NOT rounded, and T when feet were spelled --
;; carried through so the ruler is labelled in the family the length
;; was typed in.  Lenient, the way DIMSTAMP reads: the inch mark is
;; optional and may be two apostrophes, the dash after the feet mark is
;; optional, inches may be decimal, and a fraction may be spaced or
;; dashed -- 44, 44.5, 44 1/2, 4'4.5 and 4'-4 1/2" all read.  nil when
;; the text is not a measurement at all.
(defun cst:parse-len (s / n apos feetstr rest hasfeet feet inch)
  (setq s (vl-string-trim " \t" s)
        n (strlen s))
  (cond
    ((and (>= n 2) (= (substr s (1- n) 2) "''"))
     (setq s (substr s 1 (- n 2))))
    ((and (>= n 1) (= (substr s n 1) "\""))
     (setq s (substr s 1 (1- n)))))
  (setq s (vl-string-trim " \t" s) hasfeet nil feet 0.0)
  (if (setq apos (vl-string-search "'" s))
    (progn
      (setq feetstr (vl-string-trim " \t" (substr s 1 apos))
            rest    (vl-string-trim " \t-" (substr s (+ apos 2))))
      (if (cst:len-num-p feetstr)
        (setq feet (atof feetstr) hasfeet T)
        (setq rest nil)))
    (setq rest (vl-string-trim " \t" s)))
  (setq inch (if rest (cst:len-inches rest)))
  (if (and inch (or hasfeet (/= rest "")))
    (list (+ (* feet 12.0) inch) hasfeet)))

;; INCHES to the nearest eighth, as an integer count of eighths -- the
;; unit the ruler is built in.
(defun cst:len-eighths (inches)
  (fix (+ 0.5 (* 8.0 inches))))

;; Spell TOTAL-EIGHTHS out as text, in the HASFEET family.  STACKED nil
;; is the PLAIN spelling ("44 1/2\"", what the command line says);
;; STACKED T is the DRAWN one, the fraction stacked through AutoCAD's
;; \S code at the size of the text around it, for a ruler label and
;; nothing else.
(defun cst:spell-len (total-eighths hasfeet stacked / feet remain whole f8
                         g num den fr)
  (if hasfeet
    (setq feet   (/ total-eighths 96)
          remain (- total-eighths (* feet 96)))
    (setq feet 0 remain total-eighths))
  (setq whole (/ remain 8)
        f8    (- remain (* whole 8))
        num   0
        den   1)
  (if (/= f8 0)
    (progn
      (setq g (gcd f8 8))
      (setq num (/ f8 g) den (/ 8 g))))
  (setq fr (cond
             ((= num 0) "")
             ((null stacked) (strcat " " (itoa num) "/" (itoa den)))
             (T (strcat "{\\H1.0000x;\\S" (itoa num) "/" (itoa den) ";}"))))
  (strcat (if (and stacked (/= num 0)) "\\A1;" "")
          (if hasfeet (strcat (itoa feet) "'-") "")
          (itoa whole) fr "\""))

;; What to say when something typed is not a length at all.  The
;; examples are the lazy spellings on purpose: the ones worth showing
;; are the ones that save keystrokes.  A fraction is shown DASHED, never
;; spaced: at a click-or-type prompt the spacebar is Enter, so 44 1/2
;; entered 44 and handed the 1/2 to the next question as half an inch.
(defun cst:len-unread (v)
  (princ (strcat "\n\"" v "\" is not a length - try 44, 44.5, 44-1/2,"
                 " 4'4.5 or 4'-4-1/2\".")))

;; The RULER TIER an offset of OFFSET eighths from the current value
;; falls in -- 'jump for a whole inch, 'half/'quarter/'eighth for the
;; finer steps, biggest to smallest; a row's tick length and text
;; height read off it.
(defun cst:ruler-tier (offset / a m)
  (setq a (abs offset) m (rem a 8))
  (cond
    ((= m 0) 'jump)
    ((= m 4) 'half)
    ((member m '(2 6)) 'quarter)
    (T 'eighth)))

;; The nearby values to offer, as (EIGHTHS TIER) pairs: every eighth
;; for a whole inch either side, and with feet in play the 2" and 3"
;; jumps beyond that as well.  A row at or below zero is dropped.
;; Unsorted -- the ruler sorts once it also has the current row.
(defun cst:ruler-rows (total-eighths hasfeet / out i off)
  (setq out nil i 1)
  (while (<= i 8)
    (setq out (cons (list (- total-eighths i) (cst:ruler-tier i)) out))
    (setq out (cons (list (+ total-eighths i) (cst:ruler-tier i)) out))
    (setq i (1+ i)))
  (if hasfeet
    (progn
      (setq i 2)
      (while (<= i 3)
        (setq off (* i 8))
        (setq out (cons (list (- total-eighths off) 'jump) out))
        (setq out (cons (list (+ total-eighths off) 'jump) out))
        (setq i (1+ i)))))
  (vl-remove-if '(lambda (pr) (<= (car pr) 0)) out))

;; The RULER TIER a LADDER rung falls in, read off the value itself
;; rather than off a distance from the current row: a whole foot is the
;; deepest mark, a half foot the next, a quarter foot after that, and
;; everything else is a plain rung.  That is where a tape's deep marks
;; are, so a ladder of radii reads as a ruler and not as a list.
(defun cst:ladder-tier (eighths)
  (cond
    ((= 0 (rem eighths 96)) 'jump)        ; a whole foot
    ((= 0 (rem eighths 48)) 'half)        ; a half foot
    ((= 0 (rem eighths 24)) 'quarter)     ; a quarter foot
    (T 'eighth)))

;; The rungs of LADDER, given as (LO HI STEP) in inches: every step from
;; LO to HI, as the same (EIGHTHS TIER) pairs a tape's rows are.  A rung
;; at or below zero is dropped, as a tape's rows are.
;;
;; A ladder is a KNOB, and a knob is whatever a drafter left in it -- a
;; string, two numbers where three were wanted, a step of zero.  So the
;; shape is read here rather than trusted: anything that is not three
;; numbers with a positive step has no rungs, and cst:ruler-show reads
;; that as no ladder.  A settings line typed wrong costs the ruler, not
;; the command.  Unsorted -- the ruler sorts once it also has the
;; current row.
(defun cst:ladder-rows (ladder / lo hi step v out)
  (setq out nil)
  (if (and (= (type ladder) 'LIST) (= 3 (length ladder))
           (numberp (car ladder)) (numberp (cadr ladder))
           (numberp (caddr ladder)) (> (caddr ladder) 0.0))
    (progn
      (setq lo   (cst:len-eighths (car ladder))
            hi   (cst:len-eighths (cadr ladder))
            step (cst:len-eighths (caddr ladder))
            v    lo)
      (if (> step 0)
        (while (<= v hi)
          (if (> v 0) (setq out (cons (list v (cst:ladder-tier v)) out)))
          (setq v (+ v step))))))
  out)

;; Ascending by value -- the comparator the ruler sorts rows with.
(defun cst:ruler-val-lt (a b) (< (car a) (car b)))

;; What the screen is showing, as (LEFT BOTTOM WIDTH HEIGHT) in drawing
;; units: VIEWSIZE is the view's height and SCREENSIZE its aspect.
;; This is what pins the ruler to the same strip of screen at any zoom.
(defun cst:ruler-view ( / ctr vh ss aspect vw)
  (setq ctr (getvar "VIEWCTR")
        vh  (getvar "VIEWSIZE")
        ss  (getvar "SCREENSIZE"))
  (setq aspect (if (and ss (listp ss) (numberp (car ss))
                        (numberp (cadr ss)) (> (cadr ss) 0))
                 (/ (float (car ss)) (float (cadr ss)))
                 1.6))                    ; no viewport to measure
  (setq vw (* vh aspect))
  (list (- (car ctr) (/ vw 2.0)) (- (cadr ctr) (/ vh 2.0)) vw vh))

;; Which way a row reaches from a spine pinned SCREEN-X of the way
;; across the view: always toward the middle, so a ruler pinned near an
;; edge is never drawn past it.  1.0 toward higher x, -1.0 lower.
(defun cst:ruler-dir (screen-x)
  (if (> screen-x 0.5) -1.0 1.0))

;; Label height for a row of this TIER, against a row spacing of GAP,
;; the biggest label being FRAC of the spacing.
(defun cst:ruler-hgt (tier gap frac / base)
  (setq base (* gap frac))
  (cond
    ((eq tier 'half) (* base 0.8))
    ((eq tier 'quarter) (* base 0.65))
    ((eq tier 'eighth) (* base 0.5))
    (T base)))                     ; 'current and 'jump

;; Tick length for a row of this TIER, same measure.
(defun cst:ruler-tick (tier gap frac / base)
  (setq base (* gap frac))
  (cond
    ((eq tier 'half) (* base 0.75))
    ((eq tier 'quarter) (* base 0.55))
    ((eq tier 'eighth) (* base 0.35))
    (T base)))                     ; 'current and 'jump

;; The ruler is laid out in the UCS -- VIEWCTR is a UCS point, and so
;; is every click the hit test reads -- and entmake takes the WORLD.
;; So each point goes through trans on its way into the drawing: under
;; a UCS whose origin a drafter has moved to the pool's corner, the
;; ruler was drawn that far away from the view it was measured off,
;; out of sight, while the prompt still answered clicks on the empty
;; strip where it should have been.

;; A ruler stroke from (X1 Y1) to (X2 Y2) on LAY in ACI colour COL.
(defun cst:ruler-line (x1 y1 x2 y2 lay col)
  (entmakex (list '(0 . "LINE") '(100 . "AcDbEntity") (cons 8 lay)
                  (cons 62 col) '(100 . "AcDbLine")
                  (cons 10 (trans (list x1 y1 0.0) 1 0))
                  (cons 11 (trans (list x2 y2 0.0) 1 0)))))

;; The ring that marks the current row.
(defun cst:ruler-ring (x y r lay col)
  (entmakex (list '(0 . "CIRCLE") '(100 . "AcDbEntity") (cons 8 lay)
                  (cons 62 col) '(100 . "AcDbCircle")
                  (cons 10 (trans (list x y 0.0) 1 0)) (cons 40 r))))

;; A ruler label: one unwrapped MTEXT of height HGT at PT in the
;; current text style, attached top left (ATT 1) or top right (3) so
;; it grows away from the spine, and running along the UCS X axis
;; (group 11, a WORLD direction) so it reads level in a plan view of
;; that UCS.
(defun cst:ruler-label (pt hgt str lay col att)
  (entmakex (list '(0 . "MTEXT") '(100 . "AcDbEntity") (cons 8 lay)
                  (cons 62 col) '(100 . "AcDbMText")
                  (cons 10 (trans (list (car pt) (cadr pt) 0.0) 1 0))
                  (cons 40 hgt) '(41 . 0.0) (cons 71 att) '(72 . 5)
                  (cons 1 str) (cons 11 (trans '(1.0 0.0 0.0) 1 0 T))
                  '(73 . 1) '(44 . 1.0))))

;; Draw the ruler down its strip of the current view round
;; TOTAL-EIGHTHS, in the HASFEET family, on layer LAY, sized and
;; coloured by STYLE: one row per suggestion plus the ringed current
;; row among them, the whole thing centred vertically in the view.
;; LADDER nil is the tape, the eighths either side of TOTAL-EIGHTHS;
;; a (LO HI STEP) is the ladder, its rungs instead.  TOTAL-EIGHTHS may
;; be nil ON A LADDER and only there -- a ladder is the values a prompt
;; is answered with and stands whether or not one has been given yet,
;; where a tape is built round the last answer and has nothing to be
;; without it.  A rung equal to the current row is dropped, so the row
;; is ringed once rather than drawn twice.
;; Returns (ENTS BOX ROWS): the entities drawn, BOX as (XMIN XMAX YTOL)
;; for the hit test, and ROWS as (EIGHTHS ROW-Y) pairs.
(defun cst:draw-ruler (total-eighths hasfeet lay style ladder / rows n i row
                          val tier y hgt tl spx ents result view vx vy vw vh
                          gap base rcol dir far near)
  (setq rows (if ladder
               (vl-remove-if '(lambda (pr) (equal (car pr) total-eighths))
                             (cst:ladder-rows ladder))
               (cst:ruler-rows total-eighths hasfeet)))
  (if total-eighths
    (setq rows (cons (list total-eighths 'current) rows)))
  (setq rows (vl-sort rows 'cst:ruler-val-lt))
  (setq view (cst:ruler-view)
        vx   (car view)  vy (cadr view)
        vw   (caddr view) vh (cadddr view))
  (setq n    (length rows)
        gap  (* vh (nth 3 style))
        spx  (+ vx (* vw (nth 2 style)))
        dir  (cst:ruler-dir (nth 2 style))   ; rows run inward
        base (- (+ vy (/ vh 2.0)) (* gap (/ (- n 1) 2.0)))
        i    0
        ents nil
        result nil)
  (foreach row rows
    (setq val  (car row) tier (cadr row))
    (setq y    (+ base (* i gap))
          hgt  (cst:ruler-hgt tier gap (nth 4 style))
          tl   (cst:ruler-tick tier gap (nth 5 style))
          rcol (if (eq tier 'current) (nth 1 style) (nth 0 style)))
    (setq ents (cons (cst:ruler-line spx y (+ spx (* dir tl)) y lay rcol)
                     ents))
    ;; half a label's height above the tick puts it astride its own
    ;; row, and the attachment turns with the row: a label on a row
    ;; that reaches left is hung by its RIGHT edge, so it grows away
    ;; from the spine rather than back across it
    (setq ents (cons (cst:ruler-label (list (+ spx (* dir (+ tl (* gap 0.35))))
                                            (+ y (/ hgt 2.0)))
                                      hgt (cst:spell-len val hasfeet T)
                                      lay rcol (if (< dir 0.0) 3 1))
                     ents))
    (if (eq tier 'current)
      (setq ents (cons (cst:ruler-ring spx y (* gap (nth 6 style)) lay rcol)
                       ents)))
    (setq result (cons (list val y) result))
    (setq i (1+ i)))
  (setq ents (cons (cst:ruler-line spx base spx (+ base (* (- n 1) gap))
                                   lay (nth 0 style))
                   ents))
  ;; the strip a click counts as a pick in: the reach on the side the
  ;; rows run, half a spacing on the other -- the tick's own side
  (setq near (+ spx (* dir gap (nth 7 style)))
        far  (- spx (* dir (/ gap 2.0))))
  (list ents
        (list (min near far) (max near far) (/ gap 2.0))
        (reverse result)))

;; The row (if any) that PT lands on: inside the ruler's strip in X and
;; close enough in Y to one of ROWS.  Returns the row's EIGHTHS, or nil
;; when PT is empty space.
(defun cst:ruler-hit (pt box rows / r best bd d)
  (setq best nil bd nil)
  (if (and box (>= (car pt) (car box)) (<= (car pt) (cadr box)))
    (foreach r rows
      (setq d (abs (- (cadr pt) (cadr r))))
      (if (and (<= d (caddr box)) (or (null bd) (< d bd)))
        (setq best (car r) bd d))))
  best)

;; A ruler that is not up yet, to draw on LAY in STYLE.
(defun cst:ruler-new (lay style)
  (list nil nil nil nil nil lay style nil nil))

;; The ruler taken down: its entities erased and forgotten.  The family
;; and the hint flag are kept, since neither is about what is drawn; the
;; ladder is not, since it is what the next prompt asks for and the next
;; prompt says so itself.
;;
;; entdel refuses on a locked layer, and it refuses quietly -- so a
;; ruler that would not come down stayed in the drawing, and every
;; redraw added another.  The tools unlock their own ruler layer before
;; drawing on it; this is the line that says so if one gets through
;; anyway (the step routines draw on the current layer), once per
;; take-down, naming the layer the rows are left on.
(defun cst:ruler-off (state / e left)
  (setq left 0)
  (foreach e (nth 2 state)
    (if (and e (entget e) (not (entdel e))) (setq left (1+ left))))
  (if (> left 0)
    (princ (strcat "
  " (itoa left) " ruler item(s) could not be"
                   " erased - layer " (vl-princ-to-string (nth 5 state))
                   " is locked.  Unlock it and ERASE them.")))
  (list nil (nth 1 state) nil nil nil (nth 5 state) (nth 6 state)
        (nth 7 state) nil))

;; The ruler the next prompt stands beside: the tape round LEN when
;; LADDER is nil, the rungs of LADDER when it is not -- with LEN ringed
;; among them when there is one.  Drawn fresh when it is not up, or is
;; up round some other length or on some other ladder; left alone when
;; it already is what was asked for; taken down when neither is given,
;; since there is then nothing to build one out of.  Whether it is UP is
;; what is drawn, not what it stands round: a ladder with no answer yet
;; stands round nothing and is up all the same.
;; The one-line hint is said the first time a run draws one.
(defun cst:ruler-show (state len ladder / rr)
  ;; a ladder nothing can be built out of is no ladder at all, and is
  ;; dropped here rather than drawn as an empty one
  (if (and ladder (null (cst:ladder-rows ladder))) (setq ladder nil))
  (cond
    ((and (null len) (null ladder)) (cst:ruler-off state))
    ((and (nth 2 state) (equal (nth 0 state) len)
          (equal (nth 8 state) ladder)) state)
    (T
     (setq state (cst:ruler-off state))
     (setq rr (cst:draw-ruler (if len (cst:len-eighths len)) (nth 1 state)
                              (nth 5 state) (nth 6 state) ladder))
     (if (not (nth 7 state))
       (princ (strcat "\n  A ruler of " (if ladder "the usual" "nearby")
                      " lengths is beside the drawing: click a row to"
                      " take it, or type a length (44, 44-1/2, 3'8).")))
     (list len (nth 1 state) (car rr) (cadr rr) (caddr rr)
           (nth 5 state) (nth 6 state) T ladder))))

;; One length prompt beside the ruler in STATE, and every way of
;; answering it: Enter (nil back, for the caller to read as it always
;; did), a keyword out of KWS (handed back as the keyword), a typed
;; measurement in any spelling cst:parse-len reads, a click on a ruler
;; row (that row's value), or a click on empty space, which is the
;; first of two points to measure the length between.  Zero, a
;; negative and text that is not a length are refused and asked again,
;; as initget 6 used to refuse them.  Returns (VALUE STATE): the
;; answer, and the ruler as it now stands.
;;
;; READER is the one thing a caller can add to the reading: a function
;; of the typed string returning inches, for a spelling this tree reads
;; somewhere and the library does not -- SPA's "600mm".  It is tried
;; AFTER the standard spellings, so a measurement written the tree's
;; way still reads the tree's way at a prompt that has one, and what it
;; returns is refused on the same terms as anything else: zero and a
;; negative are not lengths whoever read them.  nil = no such spelling,
;; which is every caller but one.
;;
;; The caller SHOWS the ruler first -- (setq rl (cst:ruler-show rl last
;; ladder) rr (cst:ask-len prompt kws rl nil) v (car rr) rl (cadr rr)) --
;; and that order is not a nicety: an Esc inside this prompt runs the
;; caller's *error*, and what that handler can take down is the ruler
;; the CALLER's state names.  A ruler drawn in here, in a state only
;; this function held, would outlive the Esc.  The caller keeps the
;; state between prompts and takes the ruler down with cst:ruler-off
;; before a prompt that does not take it and on every way out.
(defun cst:ask-len (prompt kws state reader / pk v out done toks)
  (setq done nil out nil)
  (while (not done)
    (if kws (initget 128 kws) (initget 128))
    (setq pk (getpoint prompt))
    (if lzd:ask (lzd:ask prompt pk) pk)
    (cond
      ((null pk) (setq done T))
      ((= (type pk) 'STR)
       (cond
         ((member pk (cst:len-split (if kws kws ""))) (setq out pk done T))
         ;; a leading minus is refused here, since the reader treats a
         ;; dash as the separator in 4-1/2 and would read -5 as 5
         ((= (substr (vl-string-trim " \t" pk) 1 1) "-")
          (princ "\nA length must be more than zero."))
         ;; a fraction with nothing in front of it is almost always the
         ;; tail of 44 1/2 typed with a space -- which this prompt, a
         ;; getpoint, took as Enter after 44 -- landing on the NEXT
         ;; question.  Taken, it was half an inch there, and nothing
         ;; said so.  Refused, the drafter sees what happened and can
         ;; still give half an inch as 0-1/2 or .5
         ((and (= 1 (length (setq toks (cst:len-split
                                          (vl-string-trim " \t\"'" pk)))))
               (vl-string-search "/" (car toks)))
          (princ (strcat "\n\"" pk "\" on its own?  A space ends the answer"
                         " at this prompt - type 44-1/2, or 0-1/2 for half"
                         " an inch.")))
         ((setq v (cst:parse-len pk))
          (if (> (car v) 0.0)
            (progn
              (setq out (car v) done T)
              ;; a typed spelling picks the ruler's family -- feet typed
              ;; means feet on the ruler -- and a change relabels every
              ;; row, so the one standing is taken down here.  Down, not
              ;; forgotten: a ladder stands round no length, so there is
              ;; nothing for forgetting one to redraw
              (if (not (eq (cadr v) (nth 1 state)))
                (setq state (cst:ruler-off
                              (list (nth 0 state) (cadr v) (nth 2 state)
                                    (nth 3 state) (nth 4 state) (nth 5 state)
                                    (nth 6 state) (nth 7 state)
                                    (nth 8 state))))))
            (princ "\nA length must be more than zero.")))
         ((and reader (setq v (apply reader (list pk))))
          (if (and (numberp v) (> v 0.0))
            (setq out v done T)
            (princ "\nA length must be more than zero.")))
         (T (cst:len-unread pk))))
      ((setq v (cst:ruler-hit pk (nth 3 state) (nth 4 state)))
       (setq out (/ v 8.0) done T))
      (T
       (setq v (getdist pk "\nSecond point of the length: "))
       (if lzd:ask (lzd:ask "\nSecond point of the length: " v) v)
       (if (and (numberp v) (> v 0.0))
         (setq out v done T)
         (princ "\nA length must be more than zero.")))))
  (list out state))
;;; -------------------- end of the length ruler -------------------------

;; The scratch layer the rows are drawn on, made if it is missing.  A
;; layer of its own is what lets a drafter turn the ruler off without
;; turning anything of the chart off with it.
;; LOCKED is not left alone: entmake draws onto a locked layer but
;; entdel refuses there, so every ruler drawn stayed in the drawing
;; for good and each redraw added another copy -- and LAYISO's
;; lock-and-fade locks this layer with everything else.  It is
;; calofin scratch, so it is unlocked, said once, and left unlocked.
(defun cst:rulerlayer ( / ed fl)
  (if (not (tblsearch "LAYER" cst:*ruler-layer*))
    (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord")
                   (cons 2 cst:*ruler-layer*) '(70 . 0) '(62 . 7)
                   (cons 6 "CONTINUOUS")))
    (progn
      (setq ed (entget (tblobjname "LAYER" cst:*ruler-layer*))
            fl (cdr (assoc 70 ed)))
      (if (and fl (= 4 (logand 4 fl))
               (entmod (subst (cons 70 (- fl 4)) (assoc 70 ed) ed)))
        (princ (strcat "\nCONSTELLATION: layer " cst:*ruler-layer*
                       " was locked - unlocked so the ruler can be"
                       " taken down again.")))))
  cst:*ruler-layer*)

;; Take the ruler down -- the one call *error* and the clean exit both
;; make, so neither has to know whether one was up.  What is left is
;; the swept STATE, not nil: it carries the one-line hint's said flag,
;; and a prompt that threw it away would say the hint again at the next
;; arc.  c:CONSTELLATION clears it at the START of a run.
(defun cst:rulerkill ()
  (if cst:*ruler* (setq cst:*ruler* (cst:ruler-off cst:*ruler*))))

;; This file's knobs, in the order the ruler reads them.
(defun cst:ruler-style ()
  (list cst:*ruler-color* cst:*ruler-current-color* cst:*ruler-screen-x*
        cst:*ruler-row-frac* cst:*ruler-txt-frac* cst:*ruler-tick-frac*
        cst:*ruler-ring-frac* cst:*ruler-reach*))

;; Typed prompts cannot take keywords, so Back is typed like a value.
(defun cst:back-word-p (s)
  (member (strcase s) '("B" "BACK" "U" "UNDO")))

;; Trim leading / trailing blanks (spaces, tabs); nil-safe.
(defun cst:trim (s / i n)
  (if (null s) (setq s ""))
  (setq n (strlen s) i 1)
  (while (and (<= i n) (member (substr s i 1) '(" " "\t")))
    (setq i (1+ i)))
  (setq s (substr s i))
  (setq n (strlen s))
  (while (and (> n 0) (member (substr s n 1) '(" " "\t")))
    (setq s (substr s 1 (1- n)) n (1- n)))
  s)

;; Pad S with spaces to width W.
(defun cst:pad (s w)
  (while (< (strlen s) w) (setq s (strcat s " ")))
  s)

;;; ----------------------------------------------------------------------
;;;  Settings, undo, layers  --  the STANDARDS section 5 skeleton
;;;
;;;  Library copies again, gone in the shared/ twin -- all but
;;;  cst:sysvars, which is this file's own list of what it changes.
;;;
;;;  OSMODE is deliberately NOT in the snapshot: this command feeds no
;;;  points to any AutoCAD command (every entity here is entmade), so
;;;  there is no moment where a stray snap could grab the wrong
;;;  geometry, and the operator's own snaps stay live at the one point
;;;  they are asked for.  Nothing to zero is nothing to restore.
;;; ----------------------------------------------------------------------

(setq cst:*sysold* nil)

;; Every entity drawn as the starting-layout preview, so the error
;; handler can take it away too -- an Esc part way through the chart
;; must not leave the legend sitting in the drawing waiting for a U.
(setq cst:*preview* nil)

;; And everything drawn as the RESULT, for the same reason and for one
;; more: the run ends by asking whether the drawing looks right, and a
;; No has to take it away again before the corrected one goes down.
(setq cst:*drawn* nil)

(defun cst:sysvars () '("CMDECHO"))

(defun cst:syssave (vars / v)
  (foreach v vars
    (if (and (not (assoc v cst:*sysold*))
             (/= nil (getvar v)))
        (setq cst:*sysold*
              (append cst:*sysold* (list (cons v (getvar v))))))))

(defun cst:sysrestore ( / p)
  (foreach p cst:*sysold* (setvar (car p) (cdr p)))
  (setq cst:*sysold* nil))

;; T when MSG is a plain cancel (Esc, quit) rather than a real error.
(defun cst:error-cancel-p (msg)
  (and msg (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))

;; One undo group per command (STANDARDS section 5).  Opens only while
;; undo is recording - _Begin in a drawing with UNDO off (bit 1 of
;; UNDOCTL clear) errors out of the command - and returns nil then, so
;; the (if undo-open ...) close skips a group it does not own.
(defun cst:undobegin ()
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn (command "_.UNDO" "_Begin") T)))

(defun cst:undoend ()
  (command "_.UNDO" "_End")
  nil)

;; Create the output layer, or - when it already exists - make sure it
;; is on, thawed and unlocked.  Without this a successful run onto a
;; frozen or switched-off layer looks like the command did nothing.
;; Returns the layer NAME in every case.
(defun cst:ensure-layer (name color / rec ed flags col fixed)
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

;;; ----------------------------------------------------------------------
;;;  2-D vector helpers  --  the CALOFIN-LIB set again, copied here for
;;;  the standalone build and gone in the shared/ twin
;;; ----------------------------------------------------------------------

(defun cst:2d (p) (list (car p) (cadr p)))
(defun cst:v- (a b) (mapcar '- (cst:2d a) (cst:2d b)))
(defun cst:v+ (a b) (mapcar '+ (cst:2d a) (cst:2d b)))
(defun cst:v* (v s) (list (* (car v) s) (* (cadr v) s)))
(defun cst:dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))
(defun cst:mid (a b) (cst:v* (cst:v+ a b) 0.5))
(defun cst:vlen (v) (sqrt (cst:dot v v)))
(defun cst:d2 (a b / dx dy)                      ; squared 2-D distance
  (setq dx (- (car a) (car b)) dy (- (cadr a) (cadr b)))
  (+ (* dx dx) (* dy dy)))

;; v scaled to length 1; nil for a (near-)zero vector.
(defun cst:unit (v / l)
  (setq v (cst:2d v)
        l (cst:vlen v))
  (if (> l 1e-12) (cst:v* v (/ 1.0 l))))

(defun cst:angnorm (a)
  (while (< a 0.0) (setq a (+ a pi pi)))
  (while (>= a (+ pi pi)) (setq a (- a pi pi)))
  a)

;; smallest signed angular difference (to - from), in (-pi, pi]
(defun cst:signed-dang (from to / d)
  (setq d (cst:angnorm (- to from)))
  (if (> d pi) (- d (* 2.0 pi)) d))

;; Tangent with the angle clamped just short of +/-90 degrees, so a
;; degenerate half-turn bulge yields a huge but finite number instead
;; of dividing by zero.
(defun cst:tan (x)
  (cond ((> x  1.5697) (setq x  1.5697))    ; 89.94 deg
        ((< x -1.5697) (setq x -1.5697)))
  (/ (sin x) (cos x)))

(defun cst:circumcenter (p1 p2 p3 / ax ay bx by cx cy d)
  (setq ax (car p1) ay (cadr p1)
        bx (car p2) by (cadr p2)
        cx (car p3) cy (cadr p3)
        d  (* 2.0 (+ (* ax (- by cy)) (* bx (- cy ay)) (* cx (- ay by)))))
  (if (> (abs d) 1e-12)
    (list (/ (+ (* (+ (* ax ax) (* ay ay)) (- by cy))
                (* (+ (* bx bx) (* by by)) (- cy ay))
                (* (+ (* cx cx) (* cy cy)) (- ay by)))
             d)
          (/ (+ (* (+ (* ax ax) (* ay ay)) (- cx bx))
                (* (+ (* bx bx) (* by by)) (- ax cx))
                (* (+ (* cx cx) (* cy cy)) (- bx ax)))
             d)
          (caddr p1))))

(defun cst:nthcdr (k lst)
  (while (> k 0) (setq lst (cdr lst) k (1- k)))
  lst)

;; COUNT elements of LST starting at index K.
(defun cst:sublist (lst k count / out)
  (setq lst (cst:nthcdr k lst))
  (while (> count 0)
    (setq out   (cons (car lst) out)
          lst   (cdr lst)
          count (1- count)))
  (reverse out))

;;; ----------------------------------------------------------------------
;;;  The letters
;;;
;;;  Points are named, not numbered, because the operator says "A to C"
;;;  out loud and writes it on the sheet the same way.  The index a
;;;  letter carries is its 0-based position, which is also its place in
;;;  the clockwise ring.
;;; ----------------------------------------------------------------------

(defun cst:letter (i) (substr cst:*letters* (1+ i) 1))

;; The 0-based index of the single letter C, or nil when C is not one.
(defun cst:index (c / p)
  (if (= 1 (strlen c))
    (setq p (vl-string-search (strcase c) cst:*letters*)))
  p)

;; The name a pair of points is known by, always low letter first, so
;; "C-A" and "A-C" are the same entry and not two.
(defun cst:key (i j)
  (strcat (cst:letter (min i j)) "-" (cst:letter (max i j))))

;;; ----------------------------------------------------------------------
;;;  The chart of dims given
;;;
;;;  One entry per dim the operator has: ("A-C" 0 2 168.0) -- the name
;;;  first so plain assoc finds it, then the two indices, then the
;;;  measurement.  Absent means not measured; there is no
;;;  present-but-nil entry to tell apart from a missing one (the
;;;  three-state rule of STANDARDS section 7.1 is about a FORM store,
;;;  and this chart is not one).
;;;
;;;  Newest first, because Back undoes the last thing typed -- so
;;;  putdim always removes any older entry for the pair before consing
;;;  the new one on, and re-answering a pair moves it to the front
;;;  rather than leaving it where it was.
;;; ----------------------------------------------------------------------

(defun cst:deldim (k chart)
  (vl-remove-if '(lambda (e) (= (car e) k)) chart))

(defun cst:putdim (i j v chart / k)
  (setq k     (cst:key i j)
        chart (cst:deldim k chart))
  (cons (list k (min i j) (max i j) v) chart))

;; Every pair of N points, in reading order: A-B, A-C ... A-Z, B-C ...
(defun cst:pairs (n / out i j)
  (setq out nil i 0)
  (while (< i n)
    (setq j (1+ i))
    (while (< j n)
      (setq out (cons (list i j) out)
            j   (1+ j)))
    (setq i (1+ i)))
  (reverse out))

;; How many dims touch point I.
(defun cst:degree (i chart / d e)
  (setq d 0)
  (foreach e chart
    (if (or (= i (cadr e)) (= i (caddr e))) (setq d (1+ d))))
  d)

;; For each point, the dims leading away from it as (other distance).
;; Built once and handed to the solver, which would otherwise search
;; the whole chart for every point on every sweep.
;;
;; Every arc adds ONE MORE POINT to the layout -- its centre, index n
;; for the first arc stored, n+1 for the next -- with a dim of R to
;; each point on the arc.  That is all an arc IS to the solver: another
;; point whose distances happen to be equal, which is exactly the shape
;; the sweep already knows how to settle.  The centres carry no letter
;; and are never drawn as points.
(defun cst:adjacency (n chart arcs / rows e k c i)
  (setq rows nil)
  (repeat (+ n (length arcs)) (setq rows (cons nil rows)))
  (foreach e chart
    (setq rows (cst:setnth rows (cadr e)
                 (cons (list (caddr e) (cadddr e)) (nth (cadr e) rows))))
    (setq rows (cst:setnth rows (caddr e)
                 (cons (list (cadr e) (cadddr e)) (nth (caddr e) rows)))))
  (setq k n)
  (foreach c arcs
    (foreach i (cadr c)
      (setq rows (cst:setnth rows i
                   (cons (list k (caddr c)) (nth i rows))))
      (setq rows (cst:setnth rows k
                   (cons (list i (caddr c)) (nth k rows)))))
    (setq k (1+ k)))
  rows)

(defun cst:setnth (lst i val / k out x)
  (setq k 0 out nil)
  (foreach x lst
    (setq out (cons (if (= k i) val x) out)
          k   (1+ k)))
  (reverse out))

;;; ----------------------------------------------------------------------
;;;  Arcs
;;;
;;;  A run of points that lies on ONE radius.  Cross dims say how far
;;;  apart things are and nothing about how the wall between them
;;;  curves, so a pool with a radius end can have its points measured
;;;  perfectly and still come out as a straight-sided polygon.  An arc
;;;  says the wall is a radius, pins the points that sit on it, and is
;;;  drawn as a real arc rather than a chord.
;;;
;;;  Named CLOCKWISE, the way the letters were handed out, so a run
;;;  that crosses the end of the alphabet is unambiguous: on a
;;;  twenty-six point job Z-B is Z A B, never B all the way back round
;;;  to Z.  Two letters are a FROM and a TO with the run between them
;;;  filled in; three or more are taken as named.
;;;
;;;  Stored newest first, like the chart, so Back undoes the last one
;;;  given: (name indices radius bows-out).
;;; ----------------------------------------------------------------------

;; "A-B-C-D" -- the name a run is known by.
(defun cst:runname (idx / out k)
  (setq out "")
  (foreach k idx
    (setq out (strcat out (if (= out "") "" "-") (cst:letter k))))
  out)

;; The points S names.  Two letters are filled in clockwise between
;; them; three or more are taken as typed.  nil for anything that is
;; not at least two of this job's points.
(defun cst:parserun (s n / ls out i)
  (setq ls (cst:letters-in s n))
  (cond ((null ls) nil)
        ((< (length ls) 2) nil)
        ((> (length ls) 2) ls)
        (t (setq out (list (car ls)) i (car ls))
           (while (/= i (cadr ls))
             (setq i   (rem (1+ i) n)
                   out (cons i out)))
           (reverse out))))

(defun cst:delarc (k arcs)
  (vl-remove-if '(lambda (a) (= (car a) k)) arcs))

(defun cst:putarc (idx r bow arcs / k)
  (setq k    (cst:runname idx)
        arcs (cst:delarc k arcs))
  (cons (list k idx r bow) arcs))

;; The arcs paired with the index their centre takes in the layout --
;; n for the first arc stored, n+1 for the next -- and turned back into
;; the order they were given in, which is the order to report them in.
;; cst:adjacency hands the centres out walking the SAME stored list, so
;; the two cannot disagree about which centre belongs to which arc.
(defun cst:arcrows (n arcs / k out a)
  (setq k n out nil)
  (foreach a arcs
    (setq out (cons (cons k a) out)
          k   (1+ k)))
  out)

;;; ----------------------------------------------------------------------
;;;  Is there enough to go on?
;;;
;;;  Two separate failures, and they need separate words because the
;;;  fix is different.  A THIN point has fewer than two dims: it sits
;;;  anywhere on a circle (one dim) or anywhere at all (none), and the
;;;  answer is to measure it twice.  A CUT-OFF point has its two dims
;;;  but they only reach other cut-off points: that island is placed
;;;  perfectly well relative to itself and floats free of everything
;;;  else, and the answer is one dim bridging the two groups.
;;; ----------------------------------------------------------------------

(defun cst:thin (n chart / out i)
  (setq out nil i 0)
  (repeat n
    (if (< (cst:degree i chart) 2) (setq out (cons i out)))
    (setq i (1+ i)))
  (reverse out))

;; The points reachable from A by following dims.
(defun cst:reach (adj / seen frontier nxt i e)
  (setq seen '(0) frontier '(0))
  (while frontier
    (setq nxt nil)
    (foreach i frontier
      (foreach e (nth i adj)
        (if (not (member (car e) seen))
          (setq seen (cons (car e) seen)
                nxt  (cons (car e) nxt)))))
    (setq frontier nxt))
  seen)

(defun cst:cutoff (n adj / seen out i)
  (setq seen (cst:reach adj) out nil i 0)
  (repeat n
    (if (not (member i seen)) (setq out (cons i out)))
    (setq i (1+ i)))
  (reverse out))

;; "A, C and F" -- the way the report names a set of points.
(defun cst:namelist (idx / out n i k)
  (setq out "" n (length idx) i 0)
  (foreach k idx
    (setq out (strcat out
                      (cond ((= i 0) "")
                            ((= i (1- n)) (if (= n 2) " and " ", and "))
                            (t ", "))
                      (cst:letter k))
          i   (1+ i)))
  out)

;;; ----------------------------------------------------------------------
;;;  The starting layout
;;;
;;;  Evenly spaced round the oval inscribed in the space, CLOCKWISE
;;;  FROM THE TOP LEFT.  Top left on an oval is 135 degrees, and
;;;  clockwise means each step SUBTRACTS its share of a full turn --
;;;  the sign that makes A B C D land top-left, top-right,
;;;  bottom-right, bottom-left on a four-point job, which is the order
;;;  a pool's corners are called out in.
;;;
;;;  Coordinates are relative to the space's lower-left corner, so the
;;;  base point is added once, at the moment something is drawn.
;;; ----------------------------------------------------------------------

(defun cst:oval (n w h / a b out i ang)
  (setq a (* 0.5 w) b (* 0.5 h) out nil i 0)
  (repeat n
    (setq ang (- (* 0.75 pi) (/ (* 2.0 pi i) n))
          out (cons (list (+ a (* a (cos ang))) (+ b (* b (sin ang)))) out)
          i   (1+ i)))
  (reverse out))

;; The oval flattened: a different aspect ratio to fall out of, for a
;; shape the round start folds.  It squashes about y = 0 rather than
;; about the oval's own centre, which moves the whole start down the
;; page as well -- harmless, because the solve is translation-blind and
;; the answer is re-placed in the space at the end either way.
(defun cst:squash (pts f)
  (mapcar '(lambda (p) (list (car p) (* f (cadr p)))) pts))

;; The oval scattered.  Pseudo-random but DETERMINISTIC -- the golden
;; angle, not a random number generator -- so the same job run twice
;; gives the same drawing.
(defun cst:shake (pts amt / out i p a)
  (setq out nil i 0)
  (foreach p pts
    (setq a   (* cst:*golden* (1+ i))
          out (cons (list (+ (car p) (* amt (cos a)))
                          (+ (cadr p) (* amt (sin a))))
                    out)
          i   (1+ i)))
  (reverse out))

;; Where an arc's centre starts.  A run of THREE or more points has
;; only one centre that can be R from all of them, so the solver finds
;; it wherever it starts.  A run of TWO has two, mirror images across
;; the chord, and nothing in the distances chooses between them -- so
;; the answer to the bow question does.  Clockwise labelling puts the
;; inside of the shape to the RIGHT of the direction of travel, so an
;; arc that bows OUT of the shape has its centre to the right of
;; first-to-last.
(defun cst:arcstart (pts arc / p q r m c half h v side)
  (setq p    (nth (car (cadr arc)) pts)
        q    (nth (last (cadr arc)) pts)
        r    (caddr arc)
        m    (cst:mid p q)
        c    (distance p q)
        half (* 0.5 c)
        ;; a chord longer than the diameter has no such arc at all; the
        ;; centre starts on the chord and the report shows the radius it
        ;; had to settle for
        h    (if (> r half) (sqrt (- (* r r) (* half half))) 0.0)
        v    (cst:unit (cst:v- q p)))
  (if v
    (progn
      (setq side (if (cadddr arc)
                   (list (cadr v) (- (car v)))      ; right of travel
                   (list (- (cadr v)) (car v))))    ; left of travel
      (cst:v+ m (cst:v* side h)))
    (cst:v+ m (list 0.0 r))))

;; A starting layout plus one starting centre per arc, in the order the
;; arcs are stored -- the order cst:adjacency hands the indices out in.
(defun cst:withcentres (pts arcs / out c)
  (setq out nil)
  (foreach c arcs
    (setq out (cons (cst:arcstart pts c) out)))
  (append pts (reverse out)))

;; Put every arc centre back where the SETTLED points say it belongs.
;;
;; cst:arcstart has to guess from the starting oval, which is not the
;; shape -- so the side it picks can be the wrong one, and a centre that
;; starts on the wrong side of its chord stays there: the fit converges
;; happily to a centre that is R from the two ends and nowhere near the
;; middle.  Every failure a random-shape sweep of this solver turned up
;; was that, and only that.
;;
;; Once the sweeps have settled the LABELLED points, the guess is not
;; needed: three points on a circle have exactly one centre, so it is
;; computed rather than chosen.  A two-point arc has no third point and
;; no unique centre, so it keeps the operator's bow answer -- but taken
;; against the settled shape now, not against the oval.
(defun cst:reseed (pts n arcs / out a idx c k)
  (setq out (cst:sublist pts 0 n))
  (foreach a (cst:arcrows n arcs)
    (setq idx (caddr a)
          k   (length idx)
          c   (if (>= k 3)
                (cst:circumcenter (nth (car idx) out)
                                  (nth (nth (/ k 2) idx) out)
                                  (nth (last idx) out))))
    (if (null c) (setq c (cst:arcstart out (cdr a))))
    (setq out (append out (list (cst:2d c)))))
  out)

;;; ----------------------------------------------------------------------
;;;  The solve, stage 1: sweeps, to find the right answer
;;;
;;;  WEIGHTED STRESS MAJORIZATION -- the Guttman transform.  One sweep
;;;  moves every point to the AVERAGE of where each dim touching it
;;;  wants it to be: dim A-C of 168 wants A to sit 168 from wherever C
;;;  currently is, along the line the two currently make.  Averaging is
;;;  what makes the sweep safe -- the total error can never rise -- so
;;;  a sweep can be trusted from any start at all.
;;;
;;;  POOL's pool:relaxn sweeps its constraints ONE AT A TIME instead,
;;;  each pulling its two points a share of the way.  That is right for
;;;  a quad with six constraints on four points.  It is wrong here: a
;;;  26-point job carries up to 325 dims and a point can be in 25 of
;;;  them, so a sequential sweep spends its time undoing what the
;;;  previous constraint just did.
;;;
;;;  What sweeps are BAD at is the last few decimal places.  They
;;;  converge linearly, at a rate set by how loosely the chart ties the
;;;  points together, and a chart that is only just rigid -- a ring with
;;;  a couple of diagonals, which is a very ordinary field sheet -- can
;;;  need many thousands of them.  Stopping at a fixed cap looks like it
;;;  works: every dim comes back close, and the report blames the tape
;;;  whose dim came back least close.  That is the worst failure this
;;;  command could have, because it sends someone out to re-measure a
;;;  tape that was right.  Measured, on ring-plus-two-diagonals charts:
;;;  400 sweeps left a given dim 0.19in out on data that has an exact
;;;  answer, and getting it to a thousandth took 14,440.
;;;
;;;  So sweeps are no longer asked to finish the job.  They are asked
;;;  only to get into the right basin -- which they do in a few dozen,
;;;  and which is the thing they are uniquely good at -- and stage 2
;;;  finishes it.
;;;
;;;  Dims are weighted equally.  A tape reading is a tape reading; there
;;;  is nothing on a field sheet that says one of them is better than
;;;  another, so nothing here pretends there is.
;;; ----------------------------------------------------------------------

;; Where two points sitting exactly on top of each other should push
;; apart.  Any direction will do, but it has to be the SAME direction
;; every run, so it comes off the indices rather than a random number.
(defun cst:spread (i j / a)
  (setq a (* cst:*golden* (+ 1.0 (float i) (* 31.0 (float j)))))
  (list (cos a) (sin a)))

;; One sweep.  PTS in, PTS out; nothing is changed in place, so every
;; point moves against the SAME starting layout rather than against
;; whatever the points before it in the list have already become.
(defun cst:sweep (pts adj / out i p num den e q d el u)
  (setq out nil i 0)
  (foreach p pts
    (setq num '(0.0 0.0) den 0.0)
    (foreach e (nth i adj)
      (setq q  (nth (car e) pts)
            d  (cadr e)
            el (distance p q)
            u  (if (> el 1.0e-9)
                 (cst:v* (cst:v- p q) (/ 1.0 el))
                 (cst:spread i (car e)))
            num (cst:v+ num (cst:v+ q (cst:v* u d)))
            den (+ den 1.0)))
    (setq out (cons (if (> den 0.0) (cst:v* num (/ 1.0 den)) p) out)
          i   (1+ i)))
  (reverse out))

;; How far the furthest point moved between two layouts.
(defun cst:maxmove (a b / m i p)
  (setq m 0.0 i 0)
  (foreach p a
    (setq m (max m (distance p (nth i b)))
          i (1+ i)))
  m)

;; Sweep until nothing moves, or until the cap.  Either way this is
;; only the first stage: cst:lm finishes from wherever it stops.
(defun cst:settle (pts adj / k moved new)
  (setq k 0 moved nil)
  (while (and (< k cst:*sweeps*) (or (null moved) (> moved cst:*tol*)))
    (setq new   (cst:sweep pts adj)
          moved (cst:maxmove pts new)
          pts   new
          k     (1+ k)))
  pts)

;; Root-mean-square miss, in drawing units: how far the layout's own
;; distances sit from the ones the operator gave, averaged over
;; everything given -- every cross dim, and every arc radius, since a
;; radius is a distance to the centre and is measured the same way.
;; This is the number the whole solve is minimizing and the one the
;; report leads with.
(defun cst:rms (pts chart arcs n / s c e d a i)
  (setq s 0.0 c 0)
  (foreach e chart
    (setq d (- (distance (nth (cadr e) pts) (nth (caddr e) pts)) (cadddr e))
          s (+ s (* d d))
          c (1+ c)))
  (foreach a (cst:arcrows n arcs)
    (foreach i (caddr a)
      (setq d (- (distance (nth i pts) (nth (car a) pts)) (cadddr a))
            s (+ s (* d d))
            c (1+ c))))
  (if (> c 0) (sqrt (/ s c)) 0.0))

;;; ----------------------------------------------------------------------
;;;  The solve, stage 2: Levenberg-Marquardt, to find it EXACTLY
;;;
;;;  The same problem, written as what it is: least squares over the
;;;  residuals r = (distance drawn) - (distance given).  Each residual
;;;  touches only the four numbers that are its two points' x and y, and
;;;  its slope in each is just the unit vector along the line -- so the
;;;  normal equations are cheap to build and the step is a linear solve.
;;;  Near the answer this doubles the number of correct digits every
;;;  iteration, where a sweep adds a fixed small fraction of one; the
;;;  fourteen thousand sweeps above become seven iterations.
;;;
;;;  It is DAMPED (that is the Marquardt half) and could not work
;;;  otherwise: a constellation is free to slide and to spin, so three
;;;  directions change nothing at all and the undamped normal equations
;;;  are singular no matter how good the dims are.  The damping also
;;;  keeps the step honest far from the answer -- a step that does not
;;;  reduce the total miss is thrown away and retried with more damping,
;;;  so this stage can never make the fit worse than the sweeps left it.
;;;
;;;  Arcs need nothing of their own here.  An arc centre is a point like
;;;  any other and its radius is a distance like any other, so it lands
;;;  in the residual list beside the cross dims and is fitted with them.
;;; ----------------------------------------------------------------------

;; Every distance the layout is held to, as (i j d): one per cross dim,
;; and one per point on an arc holding it R from that arc's centre.
(defun cst:constraints (n chart arcs / out e a i)
  (setq out nil)
  (foreach e chart
    (setq out (cons (list (cadr e) (caddr e) (cadddr e)) out)))
  (foreach a (cst:arcrows n arcs)
    (foreach i (caddr a)
      (setq out (cons (list i (car a) (cadddr a)) out))))
  (reverse out))

;; Sum of squared misses -- the number the fit is minimizing.  (The
;; report leads with the RMS, which is this over the count, rooted.)
(defun cst:sqstress (pts cl / s e d)
  (setq s 0.0)
  (foreach e cl
    (setq d (- (distance (nth (car e) pts) (nth (cadr e) pts)) (caddr e))
          s (+ s (* d d))))
  s)

;; Add V to column K of the sparse row AL.
(defun cst:acc (al k v / p)
  (if (setq p (assoc k al))
    (subst (cons k (+ (cdr p) v)) p al)
    (cons (cons k v) al)))

;; The row of the damped normal equations for one unknown -- the C-th
;; coordinate (0 = x, 1 = y) of point I -- with its right-hand side
;; appended, so a row is (a0 a1 ... a<m-1> rhs).
;;
;; It is built as an (column . value) alist and flattened once at the
;; end.  The row is nearly all zeros: the only unknowns it touches are
;; point I's own two and, for each dim on point I, that neighbour's
;; two.  Accumulating straight into a 52-wide list of zeros would walk
;; it once per entry, which is what would make this too slow to use.
(defun cst:normrow (i c pts adjrow lam m / al rhs e j d p q vx vy len
                                           ux uy g col out hit)
  (setq al nil rhs 0.0 p (nth i pts))
  (foreach e adjrow
    (setq j   (car e)
          d   (cadr e)
          q   (nth j pts)
          vx  (- (car p) (car q))
          vy  (- (cadr p) (cadr q))
          len (sqrt (+ (* vx vx) (* vy vy))))
    ;; two points on top of each other have no direction to differ in;
    ;; the sweeps push them apart, so there is nothing to do here
    (if (> len 1.0e-12)
      (progn
        (setq ux  (/ vx len)
              uy  (/ vy len)
              g   (if (= c 0) ux uy)          ; slope of r in this coord
              rhs (- rhs (* g (- len d))))
        (setq al (cst:acc al (* 2 i)          (* g ux))
              al (cst:acc al (1+ (* 2 i))     (* g uy))
              al (cst:acc al (* 2 j)          (- (* g ux)))
              al (cst:acc al (1+ (* 2 j))     (- (* g uy)))))))
  ;; Marquardt damping, on the diagonal
  (setq col (+ (* 2 i) c)
        hit (assoc col al)
        al  (cst:acc al col (* lam (+ 1.0 (if hit (cdr hit) 0.0)))))
  (setq out nil col (1- m))
  (while (>= col 0)
    (setq hit (assoc col al)
          out (cons (if hit (cdr hit) 0.0) out)
          col (1- col)))
  (append out (list rhs)))

(defun cst:normeq (pts adj lam / rows i m p)
  (setq m (* 2 (length pts)) rows nil i 0)
  (foreach p pts
    (setq rows (cons (cst:normrow i 0 pts (nth i adj) lam m) rows)
          rows (cons (cst:normrow i 1 pts (nth i adj) lam m) rows)
          i    (1+ i)))
  (reverse rows))

(defun cst:butlast (lst) (reverse (cdr (reverse lst))))

(defun cst:dotlists (a b / s)
  (setq s 0.0)
  (while (and a b)
    (setq s (+ s (* (car a) (car b)))
          a (cdr a)
          b (cdr b)))
  s)

;; Solve the system whose augmented rows are ROWS, by Gaussian
;; elimination with partial pivoting.  Returns the solution as a list,
;; or nil when the system is singular (the caller answers that with
;; more damping).
;;
;; Every step walks whole rows with mapcar and drops the column it has
;; just eliminated, so nothing ever indexes into a row: AutoLISP has no
;; arrays, and an nth into a 52-wide row inside a triple loop is the
;; difference between this being usable and not.
(defun cst:linsolve (rows / m k left best bestv rest row f out xs co cs sum)
  (setq m (length rows) k 0 left rows out nil)
  (while (< k m)
    (setq best nil bestv -1.0)
    (foreach row left
      (if (> (abs (car row)) bestv)
        (setq bestv (abs (car row)) best row)))
    (if (< bestv 1.0e-12)
      (setq k m out nil left nil)              ; singular
      (progn
        (setq rest nil)
        (foreach row left
          (if (not (eq row best))
            (progn
              (setq f    (/ (car row) (car best))
                    rest (cons (cdr (mapcar '(lambda (a b) (- a (* f b)))
                                            row best))
                               rest)))))
        (setq out  (cons best out)
              left (reverse rest)
              k    (1+ k)))))
  ;; OUT holds the pivot rows shortest first, which is the LAST unknown
  ;; first; XS then grows in increasing index order, so the leftover
  ;; coefficients of a row pair off with it directly.
  (if out
    (progn
      (setq xs nil)
      (foreach row out
        (setq co  (cdr row)
              cs  (cst:butlast co)
              sum (cst:dotlists cs xs)
              xs  (cons (/ (- (last co) sum) (car row)) xs)))
      xs)))

(defun cst:addstep (pts step / out i p)
  (setq out nil i 0)
  (foreach p pts
    (setq out (cons (list (+ (car p) (nth (* 2 i) step))
                          (+ (cadr p) (nth (1+ (* 2 i)) step)))
                    out)
          i   (1+ i)))
  (reverse out))

;; Polish PTS until the misses stop shrinking.  A step is only kept when
;; it really does reduce the total miss, so this can never hand back a
;; worse layout than it was given.
(defun cst:lm (pts adj cl / lam it s taken pass rows step trial s2)
  (setq lam cst:*lm-lam*
        s   (cst:sqstress pts cl)
        it  0)
  (while (and (< it cst:*lm-iters*) (> s cst:*lm-done*))
    (setq taken nil pass 0)
    (while (and (not taken) (< pass cst:*lm-tries*))
      (setq rows (cst:normeq pts adj lam)
            step (cst:linsolve rows))
      (if step
        (progn
          (setq trial (cst:addstep pts step)
                s2    (cst:sqstress trial cl))
          (if (< s2 s)
            (setq pts   trial
                  s     s2
                  lam   (max (* lam cst:*lm-down*) cst:*lm-lammin*)
                  taken T)
            (setq lam (* lam cst:*lm-up*))))
        (setq lam (* lam cst:*lm-up*)))
      (setq pass (1+ pass)))
    ;; nothing left to win: more damping is only shrinking the step
    (setq it (if taken (1+ it) cst:*lm-iters*)))
  pts)

;; One start taken all the way through.  DIMSFIRST picks between the two
;; orders the stages can run in, and they are BOTH tried because
;; neither wins every job:
;;
;;   nil  arcs in from the off - the centres are seeded off the starting
;;        oval and settle with everything else.
;;   T    the dims settle ALONE first, and the arcs join a shape that
;;        already exists.  An arc centre is only a guess until there is
;;        a shape for it to be the centre of, and a guess that starts on
;;        the wrong side of its chord drags real points after it.
;;
;; Returns n labelled points followed by one centre per arc.
(defun cst:polish (start adj adj0 arcs n cl dimsfirst / p)
  (if dimsfirst
    (setq p (cst:withcentres (cst:settle start adj0) arcs))
    (setq p (cst:settle (cst:withcentres start arcs) adj)))
  (setq p (cst:reseed p n arcs)         ; put the centres where they go
        p (cst:settle p adj))           ; let that settle
  (cst:lm p adj cl))                    ; then land on it exactly

;; The layout that misses by least, over every start and both stagings.
;; The oval alone is a good start and usually the only one that matters;
;; the other two are here because a stress minimum is local and a folded
;; start stays folded.  With no arc declared the two stagings are the
;; same run, so only one of them is made.
(defun cst:solve (n w h chart arcs / adj adj0 cl starts best bestr p r q)
  (setq adj    (cst:adjacency n chart arcs)
        adj0   (if arcs (cst:adjacency n chart nil) adj)
        cl     (cst:constraints n chart arcs)
        starts (list (cst:oval n w h)
                     (cst:squash (cst:oval n w h) cst:*squash*)
                     (cst:shake (cst:oval n w h)
                                (* cst:*shake* (min w h))))
        best   nil
        bestr  nil)
  (foreach q starts
    (setq p (cst:polish q adj adj0 arcs n cl nil)
          r (cst:rms p chart arcs n))
    (if (or (null bestr) (< r bestr))
      (setq best p bestr r))
    (if arcs
      (progn
        (setq p (cst:polish q adj adj0 arcs n cl T)
              r (cst:rms p chart arcs n))
        (if (< r bestr) (setq best p bestr r)))))
  best)

;;; ----------------------------------------------------------------------
;;;  Which way round, which way up
;;;
;;;  Distances say nothing about either, so both are settled against
;;;  what the operator was actually shown.
;;;
;;;  N is the LABELLED point count throughout here, and the layout
;;;  handed in is longer than that -- the arc centres ride along on the
;;;  end.  Every decision below is taken from the first N and then
;;;  applied to all of them: an arc centre can legitimately sit a long
;;;  way outside the space (a shallow radius puts it further out than
;;;  the pool is long), and letting it into the bounding box or the
;;;  chirality test would drag the fit around for a point that is never
;;;  drawn.
;;; ----------------------------------------------------------------------

(defun cst:centroid (pts / sx sy n p)
  (setq sx 0.0 sy 0.0 n (length pts))
  (foreach p pts (setq sx (+ sx (car p)) sy (+ sy (cadr p))))
  (list (/ sx n) (/ sy n)))

(defun cst:centred (pts n / c)
  (setq c (cst:centroid (cst:sublist pts 0 n)))
  (mapcar '(lambda (p) (cst:v- p c)) pts))

;; Twice the signed area of the ring A-B-C-...-A.  Positive is
;; counter-clockwise in a Y-up drawing, negative is clockwise.
(defun cst:area2 (pts / s n i p q)
  (setq s 0.0 n (length pts) i 0)
  (repeat n
    (setq p (nth i pts)
          q (nth (rem (1+ i) n) pts)
          s (+ s (- (* (car p) (cadr q)) (* (car q) (cadr p))))
          i (1+ i)))
  s)

;; A constellation and its mirror image satisfy exactly the same
;; distances, so the solve can land on either.  The operator was shown
;; A, B, C running clockwise; the one that reads clockwise is drawn.
;; (Points that came out collinear have no handedness to fix, and the
;; strict > leaves them alone.)
(defun cst:unmirror (pts n)
  (if (> (cst:area2 (cst:sublist pts 0 n)) 0.0)
    (mapcar '(lambda (p) (list (- (car p)) (cadr p))) pts)
    pts))

(defun cst:spin (pts a / c s)
  (setq c (cos a) s (sin a))
  (mapcar '(lambda (p) (list (- (* (car p) c) (* (cadr p) s))
                             (+ (* (car p) s) (* (cadr p) c))))
          pts))

;; (xlo ylo xhi yhi)
(defun cst:bbox (pts / xl yl xh yh p)
  (setq p  (car pts)
        xl (car p) xh (car p) yl (cadr p) yh (cadr p))
  (foreach p pts
    (setq xl (min xl (car p)) xh (max xh (car p))
          yl (min yl (cadr p)) yh (max yh (cadr p))))
  (list xl yl xh yh))

;; How far outside a W x H space this layout reaches, in drawing units,
;; the two axes added.  Zero means it fits.
(defun cst:overflow (pts w h / bb)
  (setq bb (cst:bbox pts))
  (+ (max 0.0 (- (- (caddr bb) (car bb)) w))
     (max 0.0 (- (- (cadddr bb) (cadr bb)) h))))

;; Sum of squared distances point-for-point between two layouts.
(defun cst:sqdev (pts ref / s i p)
  (setq s 0.0 i 0)
  (foreach p pts
    (setq s (+ s (cst:d2 p (nth i ref)))
          i (1+ i)))
  s)

;; The best angle in [LO HI], sampled STEPS ways.  Two things are
;; wanted of it and they are RANKED, not blended: first it must keep
;; the points inside the space; second, among the angles that do
;; equally well at that, it must land as near as it can to the oval
;; that was previewed, so the letters stay roughly where the operator
;; last saw them.  Returns (angle overflow deviation).
(defun cst:scanrot (pts ref w h n lo hi steps
                    / k a rot lab ov dev best bov bdev)
  (setq k 0 best lo bov nil bdev nil)
  (repeat (1+ steps)
    (setq a   (+ lo (/ (* (- hi lo) k) steps))
          rot (cst:spin pts a)
          lab (cst:sublist rot 0 n)
          ov  (cst:overflow lab w h)
          dev (cst:sqdev lab ref))
    (if (or (null bov)
            (< ov (- bov 1.0e-9))
            (and (< ov (+ bov 1.0e-9)) (< dev bdev)))
      (setq best a bov ov bdev dev))
    (setq k (1+ k)))
  (list best bov bdev))

;; Turn the solved layout to sit in the space: a whole-circle sweep,
;; then a fine pass one coarse step either side of the winner, because
;; a long thin constellation in a tight space can have a window of
;; angles that fit only a fraction of a degree wide.
(defun cst:bestrot (pts ref w h n / best span)
  (setq best (car (cst:scanrot pts ref w h n
                               0.0 (* 2.0 pi) cst:*rot-coarse*))
        span (/ (* 2.0 pi) cst:*rot-coarse*))
  ;; each pass samples one grid spacing either side of the last winner,
  ;; which is where the true best has to be, and its own spacing becomes
  ;; the next window -- so the angle tightens by cst:*rot-fine*/2 a pass
  ;; and the points land on their solved distances rather than a
  ;; degree-grid approximation of them
  (repeat cst:*rot-passes*
    (setq best (car (cst:scanrot pts ref w h n (- best span) (+ best span)
                                 cst:*rot-fine*))
          span (/ (* 2.0 span) cst:*rot-fine*)))
  best)

;; Drop the finished layout into the space, its bounding box centred in
;; the rectangle.  Centring the BOX rather than the centroid is what
;; keeps a lopsided constellation off the edges.
(defun cst:place (pts base w h n / bb dx dy)
  (setq bb (cst:bbox (cst:sublist pts 0 n))
        dx (- (+ (car base) (* 0.5 (- w (- (caddr bb) (car bb)))))
              (car bb))
        dy (- (+ (cadr base) (* 0.5 (- h (- (cadddr bb) (cadr bb)))))
              (cadr bb)))
  (mapcar '(lambda (p) (list (+ (car p) dx) (+ (cadr p) dy))) pts))

;;; ----------------------------------------------------------------------
;;;  Drawing
;;; ----------------------------------------------------------------------

;; Sizes for a W x H space: the tunable share of its smaller side,
;; never below the tunable floor.
(defun cst:texth (w h) (max cst:*texth-min* (* cst:*texth* (min w h))))
(defun cst:dotr  (w h) (max cst:*dotr-min*  (* cst:*dotr*  (min w h))))
(defun cst:dimoff (w h) (* cst:*dimoff* (min w h)))

;; A point of the drawing as the WORLD point entmake wants.  The base
;; point is a click, and a click answers in the current UCS, so the
;; whole drawing -- the space, the points, the dims, the outline -- is
;; laid out in the UCS and moved into the world only here, where it is
;; written.  Without this a UCS off the world origin drew everything
;; that far from the base point clicked, and a turned one drew the
;; space square to the world instead of to the UCS it was sized in.
(defun cst:wcs (p)
  (trans (list (car p) (cadr p) 0.0) 1 0))

;; How far the current UCS is turned from the world X axis, so text and
;; blocks read along it.  Taken off the UCS X axis moved into the world
;; -- not off UCSXDIR run back into the UCS, which is (1 0 0) there
;; however far the UCS is turned, so it would always answer zero.
;; 0 in the world UCS.
(defun cst:ucsang ( / v)
  (setq v (trans '(1.0 0.0 0.0) 1 0 T))
  (atan (cadr v) (car v)))

;; plain TEXT at pt -- a WORLD point: this is cal:text's body, swapped
;; for it in the grouped build, so its one caller hands it (cst:wcs ...)
(defun cst:text (pt hgt str lay)
  (entmake
    (list '(0 . "TEXT") (cons 8 lay)
          (list 10 (car pt) (cadr pt) 0.0)
          (cons 40 hgt) (cons 1 str))))

;; entmake and hand back the ename, so the preview can erase what it
;; drew.  (cal:mtext does the same dance for the same reason -- entmake
;; returns the entity list, not a name.)
(defun cst:made (ok) (if ok (entlast)))

(defun cst:circle (p r lay)
  (entmakex (list '(0 . "CIRCLE") '(100 . "AcDbEntity") (cons 8 lay)
                  '(100 . "AcDbCircle")
                  (cons 10 (cst:wcs p)) (cons 40 r))))

;; Closed polyline through the points given, in order.  BULGES is one
;; number per vertex or nil for a straight run; a bulge bends the
;; segment LEAVING that vertex, which is where AutoCAD keeps it.
(defun cst:poly (pts bulges lay / dxf i p)
  (setq dxf (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 lay)
                  '(100 . "AcDbPolyline") (cons 90 (length pts)) '(70 . 1))
        i   0)
  (foreach p pts
    (setq dxf (append dxf (list (cons 10 (cst:2d (cst:wcs p)))))
          dxf (if (and bulges (/= 0.0 (nth i bulges)))
                (append dxf (list (cons 42 (nth i bulges))))
                dxf)
          i   (1+ i)))
  (entmakex dxf))

(defun cst:box (base w h lay)
  (cst:poly (list base
                  (cst:v+ base (list w 0.0))
                  (cst:v+ base (list w h))
                  (cst:v+ base (list 0.0 h)))
            nil lay))

;; The bulge that carries one outline segment round an arc: the tangent
;; of a quarter of the angle the segment subtends at the centre, signed
;; the way the segment travels.  A clockwise ring gives a negative
;; angle and so a negative bulge, which is AutoCAD's own convention --
;; the sign falls out of the geometry rather than being asserted.
(defun cst:bulge (p q c)
  (cst:tan (* 0.25 (cst:signed-dang (angle c p) (angle c q)))))

;; One bulge per outline vertex: zero everywhere, except where a
;; declared arc covers a segment between two points that really are
;; NEIGHBOURS in the ring.  A run named out of ring order still
;; constrains the solve -- it is the same circle -- but there is no
;; outline segment for it to bend, so it bends none.
(defun cst:bulges (pts n arcs / out a idx c i j nx)
  (setq out nil)
  (repeat n (setq out (cons 0.0 out)))
  (foreach a (cst:arcrows n arcs)
    (setq c   (nth (car a) pts)
          idx (caddr a)
          i   0)
    (while (< (1+ i) (length idx))
      (setq j  (nth i idx)
            nx (nth (1+ i) idx))
      (if (= nx (rem (1+ j) n))
        (setq out (cst:setnth out j
                    (cst:bulge (nth j pts) (nth nx pts) c))))
      (setq i (1+ i))))
  out)

;; An ALIGNED dimension between P1 and P2, its dimension line through
;; LOC.  Built by entmake, like XYPLOT's, so the layer on it is the
;; layer asked for and DIMLAYER cannot pull it somewhere else.  Group
;; 70 is 1 (aligned) + 32 (the dimension owns a block).
;;
;; There is deliberately NO group 1 text override: the dimension
;; MEASURES the geometry that was drawn.  So a dimension that disagrees
;; with its own line in the report below is a point the dims could not
;; place where the tape said, showing up on the sheet instead of only
;; in a log nobody keeps.
(defun cst:dim (p1 p2 loc lay)
  (entmakex (list '(0 . "DIMENSION") '(100 . "AcDbEntity") (cons 8 lay)
                  '(100 . "AcDbDimension")
                  (cons 10 (cst:wcs loc))
                  (cons 11 (cst:wcs loc))
                  '(70 . 33) '(1 . "")
                  '(100 . "AcDbAlignedDimension")
                  (cons 13 (cst:wcs p1))
                  (cons 14 (cst:wcs p2)))))

;; The ab_pt survey block, built if this drawing has never seen one.
;; (ABCDEF's definition, made the same way, so a drawing can hold
;; imports from both commands without a clash.)
(defun cst:ensure-block ( / sty)
  (if (not (tblsearch "BLOCK" cst:*point-block*))
    (progn
      (setq sty (if (tblsearch "STYLE" "STANDARD")
                  "STANDARD"
                  (getvar "TEXTSTYLE")))
      (entmake (list '(0 . "BLOCK") '(100 . "AcDbEntity") '(8 . "0")
                     '(100 . "AcDbBlockBegin")
                     (cons 2 cst:*point-block*) '(70 . 2)
                     '(10 0.0 0.0 0.0)
                     (cons 3 cst:*point-block*) '(1 . "")))
      (entmake '((0 . "POINT") (100 . "AcDbEntity") (8 . "0")
                 (100 . "AcDbPoint") (10 0.0 0.0 0.0)))
      (entmake (list '(0 . "ATTDEF") '(100 . "AcDbEntity") '(8 . "0")
                     '(100 . "AcDbText") '(10 1.0 -2.0 0.0) '(40 . 1.0)
                     '(1 . "0") (cons 7 sty)
                     '(100 . "AcDbAttributeDefinition")
                     '(3 . "Type_Point_Number")
                     (cons 2 cst:*point-tag*) '(70 . 4)))
      (entmake '((0 . "ENDBLK") (100 . "AcDbEntity") (8 . "0")
                 (100 . "AcDbBlockEnd")))
      (princ (strcat "\n  block \"" cst:*point-block*
                     "\" was not in this drawing - created it."))))
  (tblsearch "BLOCK" cst:*point-block*))

(defun cst:insert-pt (pt name th / rot)
  (setq rot (cst:ucsang))
  (entmake (list '(0 . "INSERT") '(100 . "AcDbEntity")
                 (cons 8 cst:*point-layer*)
                 '(100 . "AcDbBlockReference") '(66 . 1)
                 (cons 2 cst:*point-block*)
                 (cons 10 (cst:wcs pt))
                 (cons 41 th) (cons 42 th) (cons 43 th) (cons 50 rot)))
  (entmake (list '(0 . "ATTRIB") '(100 . "AcDbEntity")
                 (cons 8 cst:*point-layer*) '(100 . "AcDbText")
                 (cons 10 (cst:wcs (list (+ (car pt) th)
                                         (- (cadr pt) (* 2.0 th)))))
                 (cons 40 th) (cons 50 rot) (cons 1 name)
                 '(100 . "AcDbAttribute")
                 (cons 2 cst:*point-tag*) '(70 . 0)))
  (entmake (list '(0 . "SEQEND") '(100 . "AcDbEntity")
                 (cons 8 cst:*point-layer*))))

;;; ----------------------------------------------------------------------
;;;  The preview
;;;
;;;  Drawn before a single dim is asked for, and erased again the moment
;;;  the real positions are known.  It is not a measurement and it is
;;;  not a guess at the answer -- it is the legend, so the operator can
;;;  see which letter is which before naming a pair.
;;;
;;;  NOTHING permanent is drawn until the run finishes.  The space
;;;  rectangle is part of the preview too and gets drawn again at the
;;;  end, so a run that is backed out of or cancelled leaves the drawing
;;;  exactly as it found it.
;;; ----------------------------------------------------------------------

(defun cst:preview (n w h base / pts i p r th lab)
  (cst:unpreview)
  (cst:ensure-layer cst:*space-layer* cst:*space-color*)
  (cst:ensure-layer cst:*guide-layer* cst:*guide-color*)
  (setq r   (cst:dotr w h)
        th  (cst:texth w h)
        i   0
        pts (cst:oval n w h)
        cst:*preview* (list (cst:box base w h cst:*space-layer*)))
  (foreach p pts
    (setq p   (cst:v+ base p)
          cst:*preview* (cons (cst:circle p r cst:*guide-layer*)
                              cst:*preview*)
          lab (cst:made (cst:text (cst:wcs (list (+ (car p) r)
                                                 (+ (cadr p) r)))
                                  th (cst:letter i) cst:*guide-layer*))
          cst:*preview* (if lab (cons lab cst:*preview*) cst:*preview*)
          i   (1+ i)))
  (princ (strcat "\n  A to " (cst:letter (1- n))
                 " are shown clockwise from the top left, evenly spaced"))
  (princ "\n  round the space.  Where they really go is what the dims say.")
  (princ))

;; Safe to call at any time, including twice: an ename already gone has
;; no entget, and the list is emptied as it is swept.  The guard is not
;; decoration -- entdel TOGGLES, so a second sweep without it would put
;; everything back.
(defun cst:unpreview ( / e)
  (foreach e cst:*preview* (if (and e (entget e)) (entdel e)))
  (setq cst:*preview* nil))

;; Everything made since MARK, in creation order.  Walking forward from
;; a mark rather than collecting enames as they are made is what catches
;; the attribute and the SEQEND of an ab_pt block: those are buffered
;; until the sequence closes and do not reliably hand a name back, and a
;; redraw that missed them would leave the old labels behind.  (XYPLOT's
;; xyp:new-points walks the same way, for the same reason.)
(defun cst:since (mark / e out)
  (setq e (if mark (entnext mark) (entnext)) out nil)
  (while e
    (setq out (cons e out)
          e   (entnext e)))
  (reverse out))

(defun cst:undraw ( / e)
  (foreach e cst:*drawn* (if (and e (entget e)) (entdel e)))
  (setq cst:*drawn* nil))

;;; ----------------------------------------------------------------------
;;;  The questions
;;; ----------------------------------------------------------------------

(defun cst:banner ()
  (princ (strcat "\n\nCONSTELLATION " *constellation-version*
                 " - points placed from the dims between them."))
  (princ "\n  The space is a rectangle of known X and Y that the points")
  (princ "\n  have to sit in; the base point is its lower-left corner.")
  (princ))

;; How many points.  Three is the floor: two points share one dim and
;; neither of them then has the two a placement needs.  Twenty-six is
;; the ceiling because the labels are single letters.  The default is
;; clamped into that range HERE, at the ask: the tunables are meant to
;; be set after loading, and a cst:*defcount* set outside the range must
;; not offer a count the next line would refuse.
(defun cst:askcount ( / v dflt)
  (setq dflt (fix (max cst:*minpts* (min cst:*maxpts* cst:*defcount*))))
  (initget 6 "Back Undo")
  (setq v (getint (strcat "\nHow many points? [Back] <" (itoa dflt) ">: ")))
  (if lzd:ask (lzd:ask "cst:askcount" v) v)
  (cond ((member v '("Back" "Undo")) 'CST-BACK)
        ((null v) dflt)
        ((or (< v cst:*minpts*) (> v cst:*maxpts*))
         (princ (strcat "\n  Between " (itoa cst:*minpts*) " and "
                        (itoa cst:*maxpts*) " points - they are labelled A to "
                        (cst:letter (1- cst:*maxpts*)) "."))
         (cst:askcount))
        (t v)))

;; The base point, in the CURRENT UCS: a click answers in it, and so
;; does Enter -- <0,0> is the UCS origin, the same point typing 0,0
;; gives, rather than a world origin the drafter cannot see from the
;; prompt.  The drawing is laid out off it in the UCS and moved into
;; the world where it is written (cst:wcs).
(defun cst:askbase ( / v)
  (initget "Back Undo")
  (setq v (getpoint "\nInsertion base point [Back] <0,0>: "))
  (if lzd:ask (lzd:ask "cst:askbase" v) v)
  (cond ((member v '("Back" "Undo")) 'CST-BACK)
        ((null v) '(0.0 0.0))
        (t (cst:2d v))))

;; Every point letter in S, in the order typed.  Anything that is not
;; a letter is a separator and ignored, so "AC", "A-C", "a c" and
;; "A,C" all read the same.  nil when a letter names a point this job
;; does not have, or names one twice -- a wrong letter is a typo to be
;; told about, not a character to be quietly dropped.
(defun cst:letters-in (s n / i c k out bad)
  (setq out nil bad nil i 1)
  (repeat (strlen s)
    (setq c (substr s i 1)
          k (cst:index c))
    (if (not (null k))
      (if (or (>= k n) (member k out))
        (setq bad T)
        (setq out (cons k out))))
    (setq i (1+ i)))
  (if (not bad) (reverse out)))

;; The pair S names, low letter first.  nil unless exactly two points
;; are named.
(defun cst:parsepair (s n / ls)
  (setq ls (cst:letters-in s n))
  (if (= 2 (length ls))
    (list (min (car ls) (cadr ls)) (max (car ls) (cadr ls)))))

;; The first pair still blank, as its name; nil when the chart is full.
(defun cst:nextpair (order chart / found k p)
  (foreach p order
    (if (null found)
      (progn
        (setq k (cst:key (car p) (cadr p)))
        (if (not (assoc k chart)) (setq found k)))))
  found)

;; Which pair to dimension.  Typed, not a keyword list: a 26-point job
;; has 325 pair names and initget cannot carry them, so Back and Done
;; are typed words too and the prompt says so.  (getstring T ...): a
;; plain getstring ends at the spacebar, so "a c" arrived as "a" and
;; left the "c" to answer the re-ask -- one of the spellings the pair
;; reader takes, and one nobody could type.
(defun cst:askpair (n dflt / s)
  (setq s (cst:trim ((lambda (v) (if lzd:ask (lzd:ask (getvar "LASTPROMPT") v) v))
                      (getstring T (strcat "\n  Pair to dimension <" dflt
                                         "> (B = back, D = done): ")))))
  (cond ((= s "") (cst:parsepair dflt n))
        ((cst:back-word-p s) 'CST-BACK)
        ((member (strcase s) '("D" "DONE")) 'CST-DONE)
        ((cst:parsepair s n))
        (t (princ (strcat "\n    \"" s "\" is not a pair of these points -"
                          " two different letters"))
           (princ (strcat "\n    between A and " (cst:letter (1- n))
                          ", like " (cst:key 0 1) "."))
           (cst:askpair n dflt))))

(defun cst:charthelp (n order top)
  (if top
    (progn
      (princ (strcat "\n\n  Cross dims.  " (itoa n) " points make "
                     (itoa (length order)) " possible pairs and not one of"))
      (princ "\n  them is compulsory - give the ones the sheet carries, in")
      (princ "\n  whatever order they are written down."))
    (princ "\n\n  Cross dims - name the pair whose number was wrong:"))
  (princ "\n    Enter    takes the pair shown, so Enter over and over")
  (princ "\n             walks the whole chart in order")
  (princ "\n    A-C      jumps straight to that pair (AC and a c read too),")
  (princ "\n             and a pair given twice keeps the second answer")
  (princ "\n    D        done, no more dims")
  (princ "\n    B        undo the dim just given")
  (princ (strcat "\n  Every point needs at least two dims before the chart"
                 " will close.")))

(defun cst:saythin (short chart / i d)
  (princ "\n    Not yet - these points cannot be placed:")
  (foreach i short
    (setq d (cst:degree i chart))
    (princ (strcat "\n      " (cst:letter i) " has " (itoa d)
                   (if (= 1 d) " dim" " dims"))))
  (princ "\n    Every point needs two: with one dim a point sits anywhere")
  (princ "\n    on a circle, and with none, anywhere at all."))

(defun cst:saycut (cut)
  (princ (strcat "\n    Not yet - " (cst:namelist cut)
                 (if (= 1 (length cut)) " is" " are")
                 " only dimensioned to each other,"))
  (princ "\n    so that group is placed perfectly well against itself and")
  (princ "\n    floats free of A's.  One dim across the gap ties them")
  (princ "\n    together."))

;;; ----------------------------------------------------------------------
;;;  The arc list
;;; ----------------------------------------------------------------------

(defun cst:archelp (n top)
  (if top
    (progn
      (princ "\n\n  Arcs.  If a run of points lies on ONE radius, say so.")
      (princ "\n  Cross dims say how far apart things are and nothing about")
      (princ "\n  how the wall between them curves, so a radius end can be")
      (princ "\n  measured perfectly and still come out as a flat chord.")
      (princ "\n  An arc pins those points and is drawn as a real arc."))
    (princ "\n\n  Arcs - name the run whose radius was wrong:"))
  (princ "\n  Name the run CLOCKWISE, the way the letters were handed out:")
  (princ "\n    A-C      from A clockwise to C, so A B C")
  (princ "\n    ABC      the same run, spelled out")
  (princ (strcat "\n    " (cst:letter (1- n)) "-B      wraps round the end: "
                 (cst:letter (1- n)) " A B, not B all the way back to "
                 (cst:letter (1- n))))
  (princ "\n    Enter    done, no arcs (or no more)")
  (princ "\n    B        undo the arc just given"))

;; Which points the arc runs through.  Typed, like the pair prompt and
;; for the same reason, so Back and Done are typed words too -- and read
;; with spaces allowed, for the same reason as the pair.
(defun cst:askrun (n / str ls)
  (setq str (cst:trim
              ((lambda (v) (if lzd:ask (lzd:ask (getvar "LASTPROMPT") v) v))
                (getstring T (strcat "\n  Points on the arc <Enter = done>"
                                   " (B = back): ")))))
  (cond ((= str "") 'CST-DONE)
        ((cst:back-word-p str) 'CST-BACK)
        ((member (strcase str) '("D" "DONE")) 'CST-DONE)
        ((cst:parserun str n))
        (t (princ (strcat "\n    \"" str "\" is not a run of these points"
                          " - two or more different"))
           (princ (strcat "\n    letters between A and "
                          (cst:letter (1- n)) ", like "
                          (cst:letter 0) "-" (cst:letter 2) "."))
           (cst:askrun n))))

;; The arcs.  Returns the list, or CST-BACK when Back is pressed with
;; nothing in it yet and there is a question behind to go back to.
(defun cst:askarcs (n arcs top / done ls r bow k nm)
  (cst:archelp n top)
  (setq done nil)
  (while (not done)
    (setq ls (cst:askrun n))
    (cond
      ((eq ls 'CST-BACK)
       (cond
         (arcs
          (setq k    (car (car arcs))
                arcs (cdr arcs))
          (princ (strcat "\n    Stepping back one arc - " k
                         " is off the list again.")))
         (top (setq done T arcs 'CST-BACK))
         (t (princ "\n    Already at the first arc."))))
      ((eq ls 'CST-DONE) (setq done T))
      (t
       (setq nm (cst:runname ls)
             r  (cst:askdist 'REQ (strcat "  Radius for " nm) nil T
                             cst:*radius-ladder*))
       (if (not (eq r 'CST-BACK))
         (progn
           ;; three points on a circle of known R fix its centre
           ;; outright; two leave two centres, mirror images across the
           ;; chord, and only the operator knows which wall this is
           (setq bow (if (= 2 (length ls))
                       (cst:askyn (strcat "  Does " nm
                                          " bow out from the shape?")
                                  "Yes" T)
                       T))
           (if (not (eq bow 'CST-BACK))
             (progn
               (setq arcs (cst:putarc ls r bow arcs))
               (princ (strcat "\n    " nm " on R" (rtos r)
                              (if bow "" ", bowing in") "   ("
                              (itoa (length arcs))
                              (if (= 1 (length arcs)) " arc)"
                                  " arcs)"))))))))))
  arcs)

;; The cross-dim chart.  Returns the chart, or CST-BACK when Back is
;; pressed with nothing in it yet.
;;
;; TOP is T on the way through the questions, where Back out of an empty
;; chart means going back a QUESTION, and where a chart that fills up
;; closes itself so the walk needs no final D.  It is nil on a FIX pass,
;; re-entered from "does it look right": there is no earlier question to
;; reach, and a full chart must NOT close itself or there would be no
;; way in to change the number that was wrong.
;;
;; The same holds for a chart that is already full on the way IN: that
;; is the operator pressing Back at the arcs to change a dim, and a
;; chart that closed itself the moment it was re-entered bounced them
;; straight back to the arcs (it did).  So only a chart that fills up
;; UNDER the operator closes itself; one they came back to waits for D,
;; exactly as a fix pass does.
(defun cst:askchart (n chart arcs top / order done nxt pr v k short cut
                                        wasfull)
  (setq order   (cst:pairs n)
        done    nil
        wasfull (null (cst:nextpair order chart)))
  (cst:charthelp n order top)
  (while (not done)
    (setq nxt (cst:nextpair order chart))
    (if (and (null nxt) top (not wasfull))
      (progn (princ "\n  Every pair is given.")
             (setq pr 'CST-DONE))
      (setq pr (cst:askpair n (if nxt nxt (cst:key 0 1)))))
    (cond
      ((eq pr 'CST-BACK)
       (cond
         (chart
          (setq k     (car (car chart))
                chart (cdr chart))
          (princ (strcat "\n    Stepping back one dimension - " k
                         " is blank again.")))
         (top (setq done T chart 'CST-BACK))
         (t (princ "\n    Already at the first dimension."))))
      ((eq pr 'CST-DONE)
       (setq short (cst:thin n chart)
             cut   (if short nil
                     (cst:cutoff n (cst:adjacency n chart arcs))))
       (cond (short (cst:saythin short chart))
             (cut   (cst:saycut cut))
             (t     (setq done T))))
      (t
       ;; no ladder: this is the tape between two survey points, and
       ;; there is no short list of what one comes to
       (setq v (cst:askdist 'REQ (strcat "  " (cst:key (car pr) (cadr pr)))
                            nil T nil))
       (if (not (eq v 'CST-BACK))
         (progn
           (setq chart (cst:putdim (car pr) (cadr pr) v chart))
           (princ (strcat "\n    " (cst:key (car pr) (cadr pr)) " = "
                          (rtos v) "   (" (itoa (length chart)) " of "
                          (itoa (length order)) " given)")))))))
  chart)

;; The whole chain, with Back.  Returns (w h n base chart arcs outline).
;; The first question offers no Back (STANDARDS section 3), so there is
;; no way out of here but forward or Esc -- and Esc lands in the
;; command's *error* handler, which sweeps the preview and closes the
;; undo group.
(defun cst:ask ( / step w h n base chart arcs outline v)
  (setq step 1 chart nil arcs nil outline T)
  (while (< step 8)
    (cond
      ((= step 1)
       (setq w (cst:askdist 'REQ "Space width (X)" nil nil nil)
             step 2))
      ((= step 2)
       (setq v (cst:askdist 'REQ "Space height (Y)" nil T nil))
       (if (eq v 'CST-BACK) (setq step 1) (setq h v step 3)))
      ((= step 3)
       (setq v (cst:askcount))
       (if (eq v 'CST-BACK) (setq step 2) (setq n v step 4)))
      ((= step 4)
       (setq v (cst:askbase))
       (if (eq v 'CST-BACK) (setq step 3) (setq base v step 5)))
      ((= step 5)
       (cst:preview n w h base)
       (setq v (cst:askchart n chart arcs T))
       (if (eq v 'CST-BACK)
         (progn (cst:unpreview) (setq step 4))
         (setq chart v step 6)))
      ((= step 6)
       (setq v (cst:askarcs n arcs T))
       (if (eq v 'CST-BACK) (setq step 5) (setq arcs v step 7)))
      ((= step 7)
       (setq v (cst:askyn "Draw the outline through the points in order?"
                          (if (= cst:*def-outline* "No") "No" "Yes") T))
       (if (eq v 'CST-BACK) (setq step 6) (setq outline v step 8)))))
  (list w h n base chart arcs outline))

;;; ----------------------------------------------------------------------
;;;  Placing the dims, and the ring
;;; ----------------------------------------------------------------------

;; Neighbours in the label ring - A-B, B-C ... and the wrap Z-A.
(defun cst:neighbours (i j n)
  (or (= 1 (abs (- i j)))
      (and (= 0 (min i j)) (= (1- n) (max i j)))))

;; One aligned dimension per dim given.  A dim between two points that
;; are NEIGHBOURS in the label ring is a perimeter dim and stands off
;; outside the shape, clear of the points; every other one is a cross
;; dim and runs straight down the chord it measures, which is how a
;; cross dim is drawn on a pool sheet.
(defun cst:drawdims (pts n chart w h / ctr off e p q m v loc)
  (setq ctr (cst:centroid pts)
        off (cst:dimoff w h))
  (foreach e chart
    (setq p   (nth (cadr e) pts)
          q   (nth (caddr e) pts)
          m   (cst:mid p q)
          loc (if (cst:neighbours (cadr e) (caddr e) n)
                (progn
                  (setq v (cst:unit (cst:v- m ctr)))
                  (if v (cst:v+ m (cst:v* v off)) m))
                m))
    (cst:dim p q loc cst:*dim-layer*)))

;; Everything the run puts in the drawing, in one place so that a No to
;; "does it look right" can take it all away again and put the corrected
;; version down.  The layers and the block are made BEFORE the mark:
;; they are not part of the drawing to be swept and a redraw must not
;; keep re-announcing them.
(defun cst:draw (pts n w h base chart arcs outline / mark th i p)
  (cst:ensure-layer cst:*space-layer* cst:*space-color*)
  (cst:ensure-layer cst:*point-layer* cst:*point-color*)
  (cst:ensure-layer cst:*dim-layer* cst:*dim-color*)
  (if outline (cst:ensure-layer cst:*outline-layer* cst:*outline-color*))
  (cst:ensure-block)
  (setq mark (entlast)
        th   (cst:texth w h)
        i    0)
  (cst:box base w h cst:*space-layer*)
  (foreach p (cst:sublist pts 0 n)
    (cst:insert-pt p (cst:letter i) th)
    (setq i (1+ i)))
  (cst:drawdims pts n chart w h)
  (if outline
    (cst:poly (cst:sublist pts 0 n) (cst:bulges pts n arcs)
              cst:*outline-layer*))
  (setq cst:*drawn* (cst:since mark)))

;; Does the ring A-B-C-...-A cross itself?  Worth saying if it does:
;; the letters were handed out clockwise, so a crossing means the dims
;; put the points in a different order than the sheet named them -
;; usually two letters swapped.
(defun cst:crossing-p (pts / n i j hit a b c d)
  (setq n (length pts) i 0 hit nil)
  (while (and (< i n) (not hit))
    (setq a (nth i pts)
          b (nth (rem (1+ i) n) pts)
          j (1+ i))
    (while (and (< j n) (not hit))
      (setq c (nth j pts)
            d (nth (rem (1+ j) n) pts))
      ;; edges sharing an end always meet; only edges sharing nothing
      ;; can really cross
      (if (and (/= (rem (1+ i) n) j) (/= (rem (1+ j) n) i))
        (if (inters a b c d T) (setq hit T)))
      (setq j (1+ j)))
    (setq i (1+ i)))
  hit)

;;; ----------------------------------------------------------------------
;;;  Which dim is the wrong one
;;;
;;;  Least squares SPREADS a bad tape.  One dim read three inches long
;;;  does not come out three inches wrong -- the fit gives a little on
;;;  every dim that touches those two points, so ten dims each end up a
;;;  bit out and the report stars all ten and names none.  That is the
;;;  arithmetic working correctly and the answer being no use.
;;;
;;;  The test that finds the culprit is to leave the worst dim out and
;;;  solve again.  If everything else then comes into line, that one dim
;;;  was carrying the error by itself.  (ABCDEF makes the same argument
;;;  about dropping its fourth tape.)
;;;
;;;  It is only asked when there is something to explain AND something
;;;  to spare: below the flag nothing is wrong, and a chart with no
;;;  redundancy has no second opinion to offer -- drop a dim there and
;;;  the error simply moves somewhere else.  The answer changes nothing
;;;  that is drawn: the layout on the sheet still honours every dim the
;;;  operator gave.
;;; ----------------------------------------------------------------------

;; The dim this layout misses by most, as (entry miss).
(defun cst:worstdim (pts chart / e d best bestd)
  (setq best nil bestd 0.0)
  (foreach e chart
    (setq d (abs (- (distance (nth (cadr e) pts) (nth (caddr e) pts))
                    (cadddr e))))
    (if (or (null best) (> d bestd)) (setq best e bestd d)))
  (list best bestd))

;; How well the rest of the chart settles without BAD -- nil when it
;; does not settle, or when the chart cannot spare the dim.
(defun cst:culprit (n w h chart arcs bad / rest pts r)
  (setq rest (cst:deldim (car bad) chart))
  (if (and rest
           (null (cst:thin n rest))
           (null (cst:cutoff n (cst:adjacency n rest arcs))))
    (progn
      (setq pts (cst:solve n w h rest arcs)
            r   (max (cadr (cst:worstdim pts rest))
                     (cst:worstarc pts n arcs)))
      (if (< r cst:*flag*) r))))

;;; ----------------------------------------------------------------------
;;;  The report
;;; ----------------------------------------------------------------------

(defun cst:indices (n / out i)
  (setq out nil i 0)
  (repeat n (setq out (cons i out) i (1+ i)))
  (reverse out))

;; One line per dim: what was given, what the drawing came out at, and
;; the difference.  A line starred here is a line to go back and
;; re-measure - which of them, when several are starred, is the
;; leave-one-out test's job above.
(defun cst:report (pts n w h base chart arcs / order p k drawn off)
  (princ (strcat "\n\nCONSTELLATION " *constellation-version*))
  (princ (strcat "\n  Space   " (rtos w) " x " (rtos h)
                 ", base point " (rtos (car base)) "," (rtos (cadr base))))
  (princ (strcat "\n  Points  " (cst:namelist (cst:indices n))))
  (setq order (cst:pairs n))
  (princ (strcat "\n  Dims    " (itoa (length chart)) " given of "
                 (itoa (length order)) " possible"))
  (if arcs
    (princ (strcat "\n  Arcs    " (itoa (length arcs)) " given")))
  (princ (strcat "\n\n  " (cst:pad "pair" 8) (cst:pad "given" 15)
                 (cst:pad "drawn" 15) "off by"))
  (foreach p order
    (setq k (assoc (cst:key (car p) (cadr p)) chart))
    (if k
      (progn
        (setq drawn (distance (nth (cadr k) pts) (nth (caddr k) pts))
              off   (abs (- drawn (cadddr k))))
        (princ (strcat "\n  " (cst:pad (car k) 8)
                       (cst:pad (rtos (cadddr k)) 15)
                       (cst:pad (rtos drawn) 15)
                       (rtos off)
                       (if (> off cst:*flag*) "   **" ""))))))
  (princ))

;; The radius an arc actually came out at (the mean of its members'
;; distances to the fitted centre) and how far the worst of them sits
;; from the R given, as (drawn miss).
(defun cst:arcmeas (pts a / i d s c worst)
  (setq s 0.0 c 0 worst 0.0)
  (foreach i (caddr a)
    (setq d     (distance (nth i pts) (nth (car a) pts))
          s     (+ s d)
          c     (1+ c)
          worst (max worst (abs (- d (cadddr a))))))
  (list (if (> c 0) (/ s c) 0.0) worst))

;; The worst any arc radius came out.
(defun cst:worstarc (pts n arcs / a worst)
  (setq worst 0.0)
  (foreach a (cst:arcrows n arcs)
    (setq worst (max worst (cadr (cst:arcmeas pts a)))))
  worst)

(defun cst:arcreport (pts n arcs / a m)
  (if arcs
    (progn
      (princ (strcat "\n\n  " (cst:pad "arc" 16) (cst:pad "R given" 15)
                     (cst:pad "R drawn" 15) "off by"))
      (foreach a (cst:arcrows n arcs)
        (setq m (cst:arcmeas pts a))
        (princ (strcat "\n  " (cst:pad (cadr a) 16)
                       (cst:pad (rtos (cadddr a)) 15)
                       (cst:pad (rtos (car m)) 15)
                       (rtos (cadr m))
                       (if (> (cadr m) cst:*flag*) "   **" ""))))))
  (princ))

;;; ----------------------------------------------------------------------
;;;  The command
;;; ----------------------------------------------------------------------

(defun c:CONSTELLATION ( / *error* undo-open q w h n base chart arcs
                           outline sol ref ang pts wd worst blame rms
                           over cross happy tofix v)
  ;; TOFIX, not "fix": a local named fix would shadow the AutoLISP
  ;; builtin of that name for everything this command calls, dynamic
  ;; scope being what it is -- and cst:askcount calls (fix ...) to clamp
  ;; its default.
  (defun *error* (msg)
    ;; user settings come back FIRST so nothing below can skip them
    (cst:sysrestore)
    ;; and the legend goes with them: a cancel part way through the
    ;; chart must not leave the starting oval in the drawing
    (cst:unpreview)
    (cst:rulerkill)
    ;; command-s, never plain command: 2015+ engines reject (command)
    ;; inside *error* unless the error mode was pushed beforehand
    ;; (STANDARDS section 5), and a rejected _End leaves the group open
    (if undo-open
      (progn (vl-catch-all-apply 'command-s (list "_.UNDO" "_End"))
             (setq undo-open nil)))
    (if (and msg (not (cst:error-cancel-p msg)))
      (princ (strcat "\nCONSTELLATION error: " msg)))
    (if lzd:report (lzd:report "CONSTELLATION" *constellation-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "CONSTELLATION" *constellation-version*))
  (cst:syssave (cst:sysvars))
  ;; a fresh run, so a fresh ruler: the hint is said once a run, and
  ;; the flag that says it has been said travels in here
  (setq cst:*ruler* nil)
  (setvar "CMDECHO" 0)
  (setq undo-open (cst:undobegin))
  (cst:banner)
  (setq q       (cst:ask)
        w       (nth 0 q)
        h       (nth 1 q)
        n       (nth 2 q)
        base    (nth 3 q)
        chart   (nth 4 q)
        arcs    (nth 5 q)
        outline (nth 6 q))
  ;; the legend has done its job now that the real positions are coming
  (cst:unpreview)
  ;; ---- solve, draw, and ask whether it is right -------------------------
  ;; Round the loop again on a No.  A number typed wrong is the ordinary
  ;; case, not an exception: the operator cannot tell 24'-6" was meant to
  ;; be 24'-9" from the chart, but they can tell at a glance from the
  ;; drawing.  So the drawing IS the check, and it comes away again
  ;; before the corrected one goes down.
  (setq happy nil)
  (while (not happy)
    (princ "\n\n  Working the positions out...")
    ;; the shape the dims and arcs want, then the two things distances
    ;; cannot say: which way round (clockwise, as previewed) and which
    ;; way up (turned to sit in the space, and among the angles that do,
    ;; nearest the oval)
    (setq sol (cst:unmirror
                (cst:centred (cst:solve n w h chart arcs) n) n)
          ref (cst:centred (cst:oval n w h) n)
          ang (cst:bestrot sol ref w h n)
          pts (cst:place (cst:spin sol ang) base w h n))
    (cst:draw pts n w h base chart arcs outline)
    (setq cross (if outline (cst:crossing-p (cst:sublist pts 0 n))))
    (cst:report pts n w h base chart arcs)
    (cst:arcreport pts n arcs)
    (setq wd    (cst:worstdim pts chart)
          worst (max (cadr wd) (cst:worstarc pts n arcs))
          rms   (cst:rms pts chart arcs n)
          over  (cst:overflow (cst:sublist pts 0 n) w h)
          blame (if (> worst cst:*flag*)
                  (cst:culprit n w h chart arcs (car wd))))
    (princ (strcat "\n\n  Worst miss " (rtos worst) ", RMS " (rtos rms)
                   " over " (itoa (length chart))
                   (if (= 1 (length chart)) " dim" " dims")
                   (if arcs
                     (strcat " and " (itoa (length arcs))
                             (if (= 1 (length arcs)) " arc." " arcs."))
                     ".")))
    (if (> worst cst:*flag*)
      (progn
        (princ "\n  ** The starred lines cannot all be true at once.")
        (if blame
          (progn
            (princ (strcat "\n  ** Leave " (car (car wd)) " out and every"
                           " other dim settles to within " (rtos blame)
                           ","))
            (princ (strcat "\n  ** so " (car (car wd)) " is the one to"
                           " re-measure - the rest are only wrong"))
            (princ "\n  ** because the fit shared its error out among them.")
            (princ (strcat "\n  ** Nothing was dropped: the layout drawn"
                           " still honours every dim given.")))
          ;; no ONE reading accounts for the others, and there are two
          ;; ways that happens.  Saying only "re-measure them" would be
          ;; picking one of them without evidence - and the remedy is
          ;; the same either way, so say both and name it.
          (progn
            (princ "\n  ** No single one of them explains the rest, so")
            (princ "\n  ** either more than one reading is out, or the")
            (princ "\n  ** chart does not pin the shape down tightly")
            (princ "\n  ** enough for the fit to be sure which layout the")
            (princ "\n  ** dims meant.  More cross dims settle either."))))
      (princ (strcat "\n  Nothing missed by more than " (rtos cst:*flag*)
                     " - nothing here needs re-measuring.")))
    (if (> over cst:*over-tol*)
      (progn
        (princ (strcat "\n  ** The constellation runs " (rtos over)
                       " past the space across its two axes."))
        (princ "\n  ** It is drawn centred in the space and overhanging it."))
      (princ "\n  Every point landed inside the space."))
    (if cross
      (progn
        (princ "\n  ** The outline crosses itself, so A, B, C ... is not the")
        (princ "\n  ** order the dims put the points in - two letters are")
        (princ "\n  ** most likely swapped on the sheet.")))
    (princ (strcat "\n  " (itoa n) " points on layer " cst:*point-layer*
                   " as \"" cst:*point-block* "\" blocks, so ABHD and"))
    (princ "\n  CABHD will fit a perimeter through them as they stand.")
    ;; ---- does it look right? -------------------------------------------
    ;; No default that Enter takes by accident would be safe here: the
    ;; whole point of the question is that it be looked at.  Yes is the
    ;; shown default because a run that went well is the common one.
    (if (cst:askyn "\nDoes the drawing look right?" "Yes" nil)
      (setq happy T)
      (progn
        (cst:undraw)
        (setq tofix (cst:askkw "What needs changing?" "Dims Arcs Both"
                               "Dims/Arcs/Both" "Dims" nil))
        (if (member tofix '("Dims" "Both"))
          (progn
            (setq v (cst:askchart n chart arcs nil))
            (if (not (eq v 'CST-BACK)) (setq chart v))))
        (if (member tofix '("Arcs" "Both"))
          (progn
            (setq v (cst:askarcs n arcs nil))
            (if (not (eq v 'CST-BACK)) (setq arcs v)))))))
  ;; only a group this run opened: with UNDO off none was opened, and an
  ;; _End then would be closing a group that is not there
  (if undo-open (setq undo-open (cst:undoend)))
  (cst:sysrestore)
  (cst:rulerkill)
  (if lzd:end (lzd:end "CONSTELLATION"))
  (princ))

;; Print the loaded version.
(defun c:CONSTELLATIONVER ()
  (princ (strcat "\nCONSTELLATION " *constellation-version*
                 " (CONSTELLATION.lsp)"))
  (princ))

;; Quiet inside the whole build: LAZPASS.lsp and
;; CALOFIN-LOADER.lsp set the flag while they load their members,
;; because one file's greeting is a greeting and sixty-three of
;; them is a wall the drafter scrolls past in every drawing they
;; open.  APPLOADed alone the flag is nil and this prints, which
;; is the one time somebody wants to be told.  CALVER reports the
;; whole roster whenever it is asked.
(if (not *calofin-quiet*)
  (princ (strcat "\nCONSTELLATION.lsp " *constellation-version*
                 " loaded.  Type CONSTELLATION to place points from"
                 " their cross dims.")))
(princ)
