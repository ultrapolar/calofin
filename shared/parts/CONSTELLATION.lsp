;;; ======================================================================
;;; CONSTELLATION.lsp  --  points placed from the dims between them
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  CONSTELLATION     place labelled points from their cross dims
;;;            CONSTELLATIONVER  print the loaded version
;;;
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
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
(setq *constellation-version* "v1.3")

;;; ----------------------------------------------------------------------
;;;  Tunables
;;; ----------------------------------------------------------------------

(setq cst:*space-layer*   "CONSTELLATION-SPACE")   ; the rectangle asked for
(setq cst:*guide-layer*   "CONSTELLATION-GUIDE")   ; the starting oval, erased
(setq cst:*outline-layer* "CONSTELLATION")         ; the ring through A B C ...
(setq cst:*dim-layer*     "DIMENSION")             ; as AUTODIM and WCALST
(setq cst:*point-layer*   "POINTS")                ; as ABCDEF and XYPLOT

;; ABCDEF's survey block, so ABHD / CABHD / ABFIND / LHD / BPCALLOUT
;; read this import the same as any other.
(setq cst:*point-block* "ab_pt")
(setq cst:*point-tag*   "number")

;; Single-letter labels, so 26 is the ceiling.  3 is the floor: two
;; points share one dim and neither of them has the two that a
;; placement needs.
(setq cst:*letters*  "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
(setq cst:*minpts*   3)
(setq cst:*maxpts*   26)
(setq cst:*defcount* 4)

;; The solve runs in two stages (see "The solve" below).  Sweeps only
;; have to get the layout into the right BASIN now, which they do in a
;; few dozen; the fit itself is finished by Levenberg-Marquardt.
(setq cst:*sweeps* 120)
(setq cst:*tol*    1.0e-6)      ; drawing units of movement, per sweep

;; The fit.  Iterations are the outer Levenberg-Marquardt steps and
;; tries the damping retries inside one of them; *lm-done* is the sum
;; of squared misses below which there is nothing left to gain (about a
;; ten-millionth of an inch, RMS).
(setq cst:*lm-iters*  40)
(setq cst:*lm-tries*   8)
(setq cst:*lm-lam*  1.0e-3)     ; starting damping
(setq cst:*lm-lammin* 1.0e-12)
(setq cst:*lm-done* 1.0e-14)

;; Starts tried, best kept.  A stress minimum is LOCAL, and a
;; constellation that starts folded can stay folded, so the oval is not
;; the only thing tried.
(setq cst:*squash* 0.35)        ; second start: the oval flattened
(setq cst:*shake*  0.30)        ; third start: the oval scattered, as a
                                ; share of the smaller space dimension

;; The turn-to-fit sweep: whole circle at cst:*rot-coarse* steps, then
;; cst:*rot-passes* refining passes, each one grid spacing either side
;; of the last winner.
(setq cst:*rot-coarse* 360)
(setq cst:*rot-fine*   40)
(setq cst:*rot-passes* 3)

;; A dim that ends up further than this from what was given is starred
;; in the report -- at a sixteenth of an inch nobody re-measures, at a
;; quarter of an inch something is wrong with the sheet.
(setq cst:*flag* 0.25)

;; Drawing sizes, as shares of the smaller side of the space.
(setq cst:*texth*   0.025)      ; label / attribute height
(setq cst:*dotr*    0.008)      ; preview marker radius
(setq cst:*dimoff*  0.060)      ; how far a perimeter dim stands off

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


;; Every entity drawn as the starting-layout preview, so the error
;; handler can take it away too -- an Esc part way through the chart
;; must not leave the legend sitting in the drawing waiting for a U.
(setq cst:*preview* nil)

;; And everything drawn as the RESULT, for the same reason and for one
;; more: the run ends by asking whether the drawing looks right, and a
;; No has to take it away again before the corrected one goes down.
(setq cst:*drawn* nil)

(defun cst:sysvars () '("CMDECHO"))

;;; ----------------------------------------------------------------------
;;;  2-D vector helpers  --  the CALOFIN-LIB set again, copied here for
;;;  the standalone build and gone in the shared/ twin
;;; ----------------------------------------------------------------------

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
    (setq a   (* 2.399963229728653 (1+ i))
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
        m    (cal:mid p q)
        c    (distance p q)
        half (* 0.5 c)
        ;; a chord longer than the diameter has no such arc at all; the
        ;; centre starts on the chord and the report shows the radius it
        ;; had to settle for
        h    (if (> r half) (sqrt (- (* r r) (* half half))) 0.0)
        v    (cal:unit (cal:v- q p)))
  (if v
    (progn
      (setq side (if (cadddr arc)
                   (list (cadr v) (- (car v)))      ; right of travel
                   (list (- (cadr v)) (car v))))    ; left of travel
      (cal:v+ m (cal:v* side h)))
    (cal:v+ m (list 0.0 r))))

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
  (setq out (cal:sublist pts 0 n))
  (foreach a (cst:arcrows n arcs)
    (setq idx (caddr a)
          k   (length idx)
          c   (if (>= k 3)
                (cal:circumcenter (nth (car idx) out)
                                  (nth (nth (/ k 2) idx) out)
                                  (nth (last idx) out))))
    (if (null c) (setq c (cst:arcstart out (cdr a))))
    (setq out (append out (list (cal:2d c)))))
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
  (setq a (* 2.399963229728653 (+ 1.0 (float i) (* 31.0 (float j)))))
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
                 (cal:v* (cal:v- p q) (/ 1.0 el))
                 (cst:spread i (car e)))
            num (cal:v+ num (cal:v+ q (cal:v* u d)))
            den (+ den 1.0)))
    (setq out (cons (if (> den 0.0) (cal:v* num (/ 1.0 den)) p) out)
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
                  lam   (max (* lam 0.1) cst:*lm-lammin*)
                  taken T)
            (setq lam (* lam 10.0))))
        (setq lam (* lam 10.0)))
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
  (setq c (cst:centroid (cal:sublist pts 0 n)))
  (mapcar '(lambda (p) (cal:v- p c)) pts))

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
  (if (> (cst:area2 (cal:sublist pts 0 n)) 0.0)
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
    (setq s (+ s (cal:d2 p (nth i ref)))
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
          lab (cal:sublist rot 0 n)
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
  (setq bb (cst:bbox (cal:sublist pts 0 n))
        dx (- (+ (car base) (* 0.5 (- w (- (caddr bb) (car bb)))))
              (car bb))
        dy (- (+ (cadr base) (* 0.5 (- h (- (cadddr bb) (cadr bb)))))
              (cadr bb)))
  (mapcar '(lambda (p) (list (+ (car p) dx) (+ (cadr p) dy))) pts))

;;; ----------------------------------------------------------------------
;;;  Drawing
;;; ----------------------------------------------------------------------

(defun cst:texth (w h) (max 0.5 (* cst:*texth* (min w h))))
(defun cst:dotr  (w h) (max 0.1 (* cst:*dotr*  (min w h))))
(defun cst:dimoff (w h) (* cst:*dimoff* (min w h)))

;; entmake and hand back the ename, so the preview can erase what it
;; drew.  (cal:mtext does the same dance for the same reason -- entmake
;; returns the entity list, not a name.)
(defun cst:made (ok) (if ok (entlast)))

(defun cst:circle (p r lay)
  (entmakex (list '(0 . "CIRCLE") '(100 . "AcDbEntity") (cons 8 lay)
                  '(100 . "AcDbCircle")
                  (list 10 (car p) (cadr p) 0.0) (cons 40 r))))

;; Closed polyline through the points given, in order.  BULGES is one
;; number per vertex or nil for a straight run; a bulge bends the
;; segment LEAVING that vertex, which is where AutoCAD keeps it.
(defun cst:poly (pts bulges lay / dxf i p)
  (setq dxf (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 lay)
                  '(100 . "AcDbPolyline") (cons 90 (length pts)) '(70 . 1))
        i   0)
  (foreach p pts
    (setq dxf (append dxf (list (cons 10 (cal:2d p))))
          dxf (if (and bulges (/= 0.0 (nth i bulges)))
                (append dxf (list (cons 42 (nth i bulges))))
                dxf)
          i   (1+ i)))
  (entmakex dxf))

(defun cst:box (base w h lay)
  (cst:poly (list base
                  (cal:v+ base (list w 0.0))
                  (cal:v+ base (list w h))
                  (cal:v+ base (list 0.0 h)))
            nil lay))

;; The bulge that carries one outline segment round an arc: the tangent
;; of a quarter of the angle the segment subtends at the centre, signed
;; the way the segment travels.  A clockwise ring gives a negative
;; angle and so a negative bulge, which is AutoCAD's own convention --
;; the sign falls out of the geometry rather than being asserted.
(defun cst:bulge (p q c)
  (cal:tan (* 0.25 (cal:signed-dang (angle c p) (angle c q)))))

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
                  (list 10 (car loc) (cadr loc) 0.0)
                  (list 11 (car loc) (cadr loc) 0.0)
                  '(70 . 33) '(1 . "")
                  '(100 . "AcDbAlignedDimension")
                  (list 13 (car p1) (cadr p1) 0.0)
                  (list 14 (car p2) (cadr p2) 0.0))))

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

(defun cst:insert-pt (pt name th)
  (entmake (list '(0 . "INSERT") '(100 . "AcDbEntity")
                 (cons 8 cst:*point-layer*)
                 '(100 . "AcDbBlockReference") '(66 . 1)
                 (cons 2 cst:*point-block*)
                 (list 10 (car pt) (cadr pt) 0.0)
                 (cons 41 th) (cons 42 th) (cons 43 th)))
  (entmake (list '(0 . "ATTRIB") '(100 . "AcDbEntity")
                 (cons 8 cst:*point-layer*) '(100 . "AcDbText")
                 (list 10 (+ (car pt) th) (- (cadr pt) (* 2.0 th)) 0.0)
                 (cons 40 th) (cons 1 name) '(100 . "AcDbAttribute")
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
  (cal:ensure-layer cst:*space-layer* 8)
  (cal:ensure-layer cst:*guide-layer* 4)
  (setq r   (cst:dotr w h)
        th  (cst:texth w h)
        i   0
        pts (cst:oval n w h)
        cst:*preview* (list (cst:box base w h cst:*space-layer*)))
  (foreach p pts
    (setq p   (cal:v+ base p)
          cst:*preview* (cons (cst:circle p r cst:*guide-layer*)
                              cst:*preview*)
          lab (cst:made (cal:text (list (+ (car p) r) (+ (cadr p) r))
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
;; the ceiling because the labels are single letters.
(defun cst:askcount ( / v)
  (initget 6 "Back Undo")
  (setq v (getint (strcat "\nHow many points? [Back] <"
                          (itoa cst:*defcount*) ">: ")))
  (cond ((member v '("Back" "Undo")) 'CAL-BACK)
        ((null v) cst:*defcount*)
        ((or (< v cst:*minpts*) (> v cst:*maxpts*))
         (princ (strcat "\n  Between " (itoa cst:*minpts*) " and "
                        (itoa cst:*maxpts*) " points - they are labelled A to "
                        (cst:letter (1- cst:*maxpts*)) "."))
         (cst:askcount))
        (t v)))

(defun cst:askbase ( / v)
  (initget "Back Undo")
  (setq v (getpoint "\nInsertion base point [Back] <0,0>: "))
  (cond ((member v '("Back" "Undo")) 'CAL-BACK)
        ((null v) '(0.0 0.0))
        (t (cal:2d v))))

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
;; are typed words too and the prompt says so.
(defun cst:askpair (n dflt / s)
  (setq s (cal:trim (getstring (strcat "\n  Pair to dimension <" dflt
                                       "> (B = back, D = done): "))))
  (cond ((= s "") (cst:parsepair dflt n))
        ((cal:back-word-p s) 'CAL-BACK)
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
;; for the same reason, so Back and Done are typed words too.
(defun cst:askrun (n / str ls)
  (setq str (cal:trim
              (getstring (strcat "\n  Points on the arc <Enter = done>"
                                 " (B = back): "))))
  (cond ((= str "") 'CST-DONE)
        ((cal:back-word-p str) 'CAL-BACK)
        ((member (strcase str) '("D" "DONE")) 'CST-DONE)
        ((cst:parserun str n))
        (t (princ (strcat "\n    \"" str "\" is not a run of these points"
                          " - two or more different"))
           (princ (strcat "\n    letters between A and "
                          (cst:letter (1- n)) ", like "
                          (cst:letter 0) "-" (cst:letter 2) "."))
           (cst:askrun n))))

;; The arcs.  Returns the list, or CAL-BACK when Back is pressed with
;; nothing in it yet and there is a question behind to go back to.
(defun cst:askarcs (n arcs top / done ls r bow k nm)
  (cst:archelp n top)
  (setq done nil)
  (while (not done)
    (setq ls (cst:askrun n))
    (cond
      ((eq ls 'CAL-BACK)
       (cond
         (arcs
          (setq k    (car (car arcs))
                arcs (cdr arcs))
          (princ (strcat "\n    Stepping back one arc - " k
                         " is off the list again.")))
         (top (setq done T arcs 'CAL-BACK))
         (t (princ "\n    Already at the first arc."))))
      ((eq ls 'CST-DONE) (setq done T))
      (t
       (setq nm (cst:runname ls)
             r  (cal:askdist 'REQ (strcat "  Radius for " nm) nil T))
       (if (not (eq r 'CAL-BACK))
         (progn
           ;; three points on a circle of known R fix its centre
           ;; outright; two leave two centres, mirror images across the
           ;; chord, and only the operator knows which wall this is
           (setq bow (if (= 2 (length ls))
                       (cal:askyn (strcat "  Does " nm
                                          " bow out from the shape?")
                                  "Yes" T)
                       T))
           (if (not (eq bow 'CAL-BACK))
             (progn
               (setq arcs (cst:putarc ls r bow arcs))
               (princ (strcat "\n    " nm " on R" (rtos r)
                              (if bow "" ", bowing in") "   ("
                              (itoa (length arcs))
                              (if (= 1 (length arcs)) " arc)"
                                  " arcs)"))))))))))
  arcs)

;; The cross-dim chart.  Returns the chart, or CAL-BACK when Back is
;; pressed with nothing in it yet.
;;
;; TOP is T on the way through the questions, where Back out of an empty
;; chart means going back a QUESTION, and where a chart that fills up
;; closes itself so the walk needs no final D.  It is nil on a FIX pass,
;; re-entered from "does it look right": there is no earlier question to
;; reach, and a full chart must NOT close itself or there would be no
;; way in to change the number that was wrong.
(defun cst:askchart (n chart arcs top / order done nxt pr v k short cut)
  (setq order (cst:pairs n) done nil)
  (cst:charthelp n order top)
  (while (not done)
    (setq nxt (cst:nextpair order chart))
    (if (and (null nxt) top)
      (progn (princ "\n  Every pair is given.")
             (setq pr 'CST-DONE))
      (setq pr (cst:askpair n (if nxt nxt (cst:key 0 1)))))
    (cond
      ((eq pr 'CAL-BACK)
       (cond
         (chart
          (setq k     (car (car chart))
                chart (cdr chart))
          (princ (strcat "\n    Stepping back one dimension - " k
                         " is blank again.")))
         (top (setq done T chart 'CAL-BACK))
         (t (princ "\n    Already at the first dimension."))))
      ((eq pr 'CST-DONE)
       (setq short (cst:thin n chart)
             cut   (if short nil
                     (cst:cutoff n (cst:adjacency n chart arcs))))
       (cond (short (cst:saythin short chart))
             (cut   (cst:saycut cut))
             (t     (setq done T))))
      (t
       (setq v (cal:askdist 'REQ (strcat "  " (cst:key (car pr) (cadr pr)))
                            nil T))
       (if (not (eq v 'CAL-BACK))
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
       (setq w (cal:askdist 'REQ "Space width (X)" nil nil)
             step 2))
      ((= step 2)
       (setq v (cal:askdist 'REQ "Space height (Y)" nil T))
       (if (eq v 'CAL-BACK) (setq step 1) (setq h v step 3)))
      ((= step 3)
       (setq v (cst:askcount))
       (if (eq v 'CAL-BACK) (setq step 2) (setq n v step 4)))
      ((= step 4)
       (setq v (cst:askbase))
       (if (eq v 'CAL-BACK) (setq step 3) (setq base v step 5)))
      ((= step 5)
       (cst:preview n w h base)
       (setq v (cst:askchart n chart arcs T))
       (if (eq v 'CAL-BACK)
         (progn (cst:unpreview) (setq step 4))
         (setq chart v step 6)))
      ((= step 6)
       (setq v (cst:askarcs n arcs T))
       (if (eq v 'CAL-BACK) (setq step 5) (setq arcs v step 7)))
      ((= step 7)
       (setq v (cal:askyn "Draw the outline through the points in order?"
                          "Yes" T))
       (if (eq v 'CAL-BACK) (setq step 6) (setq outline v step 8)))))
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
          m   (cal:mid p q)
          loc (if (cst:neighbours (cadr e) (caddr e) n)
                (progn
                  (setq v (cal:unit (cal:v- m ctr)))
                  (if v (cal:v+ m (cal:v* v off)) m))
                m))
    (cst:dim p q loc cst:*dim-layer*)))

;; Everything the run puts in the drawing, in one place so that a No to
;; "does it look right" can take it all away again and put the corrected
;; version down.  The layers and the block are made BEFORE the mark:
;; they are not part of the drawing to be swept and a redraw must not
;; keep re-announcing them.
(defun cst:draw (pts n w h base chart arcs outline / mark th i p)
  (cal:ensure-layer cst:*space-layer* 8)
  (cal:ensure-layer cst:*point-layer* 2)
  (cal:ensure-layer cst:*dim-layer* 2)
  (if outline (cal:ensure-layer cst:*outline-layer* 3))
  (cst:ensure-block)
  (setq mark (entlast)
        th   (cst:texth w h)
        i    0)
  (cst:box base w h cst:*space-layer*)
  (foreach p (cal:sublist pts 0 n)
    (cst:insert-pt p (cst:letter i) th)
    (setq i (1+ i)))
  (cst:drawdims pts n chart w h)
  (if outline
    (cst:poly (cal:sublist pts 0 n) (cst:bulges pts n arcs)
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
  (princ (strcat "\n\n  " (cal:pad "pair" 8) (cal:pad "given" 15)
                 (cal:pad "drawn" 15) "off by"))
  (foreach p order
    (setq k (assoc (cst:key (car p) (cadr p)) chart))
    (if k
      (progn
        (setq drawn (distance (nth (cadr k) pts) (nth (caddr k) pts))
              off   (abs (- drawn (cadddr k))))
        (princ (strcat "\n  " (cal:pad (car k) 8)
                       (cal:pad (rtos (cadddr k)) 15)
                       (cal:pad (rtos drawn) 15)
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
      (princ (strcat "\n\n  " (cal:pad "arc" 16) (cal:pad "R given" 15)
                     (cal:pad "R drawn" 15) "off by"))
      (foreach a (cst:arcrows n arcs)
        (setq m (cst:arcmeas pts a))
        (princ (strcat "\n  " (cal:pad (cadr a) 16)
                       (cal:pad (rtos (cadddr a)) 15)
                       (cal:pad (rtos (car m)) 15)
                       (rtos (cadr m))
                       (if (> (cadr m) cst:*flag*) "   **" ""))))))
  (princ))

;;; ----------------------------------------------------------------------
;;;  The command
;;; ----------------------------------------------------------------------

(defun c:CONSTELLATION ( / *error* undo-open q w h n base chart arcs
                           outline sol ref ang pts wd worst blame rms
                           over cross happy fix v)
  (defun *error* (msg)
    ;; user settings come back FIRST so nothing below can skip them
    (cal:sysrestore)
    ;; and the legend goes with them: a cancel part way through the
    ;; chart must not leave the starting oval in the drawing
    (cst:unpreview)
    (if undo-open (setq undo-open (cal:undoend)))
    (if (and msg (not (cal:error-cancel-p msg)))
      (princ (strcat "\nCONSTELLATION error: " msg)))
    (princ))
  (cal:syssave (cst:sysvars))
  (setvar "CMDECHO" 0)
  (setq undo-open (cal:undobegin))
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
    (setq cross (if outline (cst:crossing-p (cal:sublist pts 0 n))))
    (cst:report pts n w h base chart arcs)
    (cst:arcreport pts n arcs)
    (setq wd    (cst:worstdim pts chart)
          worst (max (cadr wd) (cst:worstarc pts n arcs))
          rms   (cst:rms pts chart arcs n)
          over  (cst:overflow (cal:sublist pts 0 n) w h)
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
    (if (> over 1.0e-6)
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
    (if (cal:askyn "\nDoes the drawing look right?" "Yes" nil)
      (setq happy T)
      (progn
        (cst:undraw)
        (setq fix (cal:askkw "What needs changing?" "Dims Arcs Both"
                             "Dims/Arcs/Both" "Dims" nil))
        (if (member fix '("Dims" "Both"))
          (progn
            (setq v (cst:askchart n chart arcs nil))
            (if (not (eq v 'CAL-BACK)) (setq chart v))))
        (if (member fix '("Arcs" "Both"))
          (progn
            (setq v (cst:askarcs n arcs nil))
            (if (not (eq v 'CAL-BACK)) (setq arcs v)))))))
  (setq undo-open (cal:undoend))
  (cal:sysrestore)
  (princ))

;; Print the loaded version.
(defun c:CONSTELLATIONVER ()
  (princ (strcat "\nCONSTELLATION " *constellation-version*
                 " (CONSTELLATION.lsp)"))
  (princ))

(princ (strcat "\nCONSTELLATION.lsp " *constellation-version*
               " loaded.  Type CONSTELLATION to place points from"
               " their cross dims."))
(princ)
