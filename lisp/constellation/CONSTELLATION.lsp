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
;;;   5. THE SOLVE, then the drawing: an ab_pt survey point per letter,
;;;      an aligned dimension per dim given, and the space itself.
;;;
;;; WHAT THE SOLVER DOES.  The dims are almost never exactly consistent
;;; -- a tape reads a sixteenth long, a corner is measured to the
;;; coping instead of the wall -- so there is usually NO layout that
;;; satisfies all of them.  What is computed is the layout that misses
;;; by as little as possible, by weighted stress majorization, and the
;;; report says how far each dim ended up from what was given.  A dim
;;; that will not come into line is a dim to go back and re-measure,
;;; which is the most useful thing this command can tell anyone.
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
(setq *constellation-version* "v1.0")

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

;; The solve.  A sweep costs one pass over the dims given, and the loop
;; stops early the moment nothing moves further than cst:*tol*, which
;; is what it normally does long before the cap.
(setq cst:*sweeps* 400)
(setq cst:*tol*    1.0e-6)      ; drawing units of movement, per sweep

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

(defun cst:askkw (msg kws shown dflt back / v)
  (initget (if dflt 0 (if back 0 1))
           (if back (strcat kws " Back Undo") kws))
  (setq v (getkword (strcat "\n" msg " [" shown
                            (if back "/Back" "") "]"
                            (if dflt (strcat " <" dflt ">") "") ": ")))
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
(defun cst:askdist (kind msg dflt back / v kw)
  ;; Undo is accepted everywhere Back is, as a hidden synonym
  (setq kw (cond ((eq kind 'REQ) (if back "Back Undo" nil))
                 (back "NA Back Undo")
                 (t "NA")))
  ;; REQ always rejects zero - offering Back must not loosen what
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
  (cond ((and (= (type v) 'STR) (member v '("Back" "Undo"))) 'CST-BACK)
        ((= (type v) 'STR) nil)               ; NA
        ((and (null v) (eq kind 'SUG)) dflt)  ; Enter took the suggestion
        (t v)))

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

(defun cst:sysvars () '("CMDECHO"))

(defun cst:syssave (vars / v)
  (if (not cst:*sysold*)
      (foreach v vars
        (if (/= nil (getvar v))
            (setq cst:*sysold*
                  (append cst:*sysold* (list (cons v (getvar v)))))))))

(defun cst:sysrestore ( / p)
  (foreach p cst:*sysold* (setvar (car p) (cdr p)))
  (setq cst:*sysold* nil))

;; T when MSG is a plain cancel (Esc, quit) rather than a real error.
(defun cst:error-cancel-p (msg)
  (and msg (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))

(defun cst:undobegin ()
  (command "_.UNDO" "_Begin")
  T)

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
(defun cst:adjacency (n chart / rows e)
  (setq rows nil)
  (repeat n (setq rows (cons nil rows)))
  (foreach e chart
    (setq rows (cst:setnth rows (cadr e)
                 (cons (list (caddr e) (cadddr e)) (nth (cadr e) rows))))
    (setq rows (cst:setnth rows (caddr e)
                 (cons (list (cadr e) (cadddr e)) (nth (caddr e) rows)))))
  rows)

(defun cst:setnth (lst i val / k out x)
  (setq k 0 out nil)
  (foreach x lst
    (setq out (cons (if (= k i) val x) out)
          k   (1+ k)))
  (reverse out))

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

;;; ----------------------------------------------------------------------
;;;  The solve
;;;
;;;  WEIGHTED STRESS MAJORIZATION -- the Guttman transform.  One sweep
;;;  moves every point to the AVERAGE of where each dim touching it
;;;  wants it to be: dim A-C of 168 wants A to sit 168 from wherever C
;;;  currently is, along the line the two currently make.  Averaging is
;;;  what makes the sweep safe -- the total error can never rise -- so
;;;  the loop simply runs until nothing moves.
;;;
;;;  POOL's pool:relaxn sweeps its constraints ONE AT A TIME instead,
;;;  each pulling its two points a share of the way.  That is right for
;;;  a quad with six constraints on four points.  It is wrong here: a
;;;  26-point job carries up to 325 dims and a point can be in 25 of
;;;  them, so a sequential sweep spends its time undoing what the
;;;  previous constraint just did.  The averaging form settles the same
;;;  answer in a fraction of the sweeps, which is why this file has its
;;;  own solver rather than calling POOL's.
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

;; Sweep until nothing moves, or until the cap.
(defun cst:settle (pts adj / k moved new)
  (setq k 0 moved nil)
  (while (and (< k cst:*sweeps*) (or (null moved) (> moved cst:*tol*)))
    (setq new   (cst:sweep pts adj)
          moved (cst:maxmove pts new)
          pts   new
          k     (1+ k)))
  pts)

;; Root-mean-square miss, in drawing units: how far the layout's own
;; distances sit from the ones the operator gave, averaged over the
;; dims given.  This is the number the whole solve is minimizing and
;; the one the report leads with.
(defun cst:rms (pts chart / s c e d)
  (setq s 0.0 c 0)
  (foreach e chart
    (setq d (- (distance (nth (cadr e) pts) (nth (caddr e) pts)) (cadddr e))
          s (+ s (* d d))
          c (1+ c)))
  (if (> c 0) (sqrt (/ s c)) 0.0))

;; The layout that misses by least, out of the three starts.  The oval
;; alone is a good start and usually the only one that matters; the
;; other two are here because a stress minimum is local and a folded
;; start stays folded.
(defun cst:solve (n w h chart / adj starts best bestr p r)
  (setq adj    (cst:adjacency n chart)
        starts (list (cst:oval n w h)
                     (cst:squash (cst:oval n w h) cst:*squash*)
                     (cst:shake (cst:oval n w h)
                                (* cst:*shake* (min w h))))
        best   nil
        bestr  nil)
  (foreach p starts
    (setq p (cst:settle p adj)
          r (cst:rms p chart))
    (if (or (null bestr) (< r bestr))
      (setq best p bestr r)))
  best)

;;; ----------------------------------------------------------------------
;;;  Which way round, which way up
;;;
;;;  Distances say nothing about either, so both are settled against
;;;  what the operator was actually shown.
;;; ----------------------------------------------------------------------

(defun cst:centroid (pts / sx sy n p)
  (setq sx 0.0 sy 0.0 n (length pts))
  (foreach p pts (setq sx (+ sx (car p)) sy (+ sy (cadr p))))
  (list (/ sx n) (/ sy n)))

(defun cst:centred (pts / c)
  (setq c (cst:centroid pts))
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
(defun cst:unmirror (pts)
  (if (> (cst:area2 pts) 0.0)
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
(defun cst:scanrot (pts ref w h lo hi steps / k a rot ov dev best bov bdev)
  (setq k 0 best lo bov nil bdev nil)
  (repeat (1+ steps)
    (setq a   (+ lo (/ (* (- hi lo) k) steps))
          rot (cst:spin pts a)
          ov  (cst:overflow rot w h)
          dev (cst:sqdev rot ref))
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
(defun cst:bestrot (pts ref w h / best span)
  (setq best (car (cst:scanrot pts ref w h 0.0 (* 2.0 pi) cst:*rot-coarse*))
        span (/ (* 2.0 pi) cst:*rot-coarse*))
  ;; each pass samples one grid spacing either side of the last winner,
  ;; which is where the true best has to be, and its own spacing becomes
  ;; the next window -- so the angle tightens by cst:*rot-fine*/2 a pass
  ;; and the points land on their solved distances rather than a
  ;; degree-grid approximation of them
  (repeat cst:*rot-passes*
    (setq best (car (cst:scanrot pts ref w h (- best span) (+ best span)
                                 cst:*rot-fine*))
          span (/ (* 2.0 span) cst:*rot-fine*)))
  best)

;; Drop the finished layout into the space, its bounding box centred in
;; the rectangle.  Centring the BOX rather than the centroid is what
;; keeps a lopsided constellation off the edges.
(defun cst:place (pts base w h / bb dx dy)
  (setq bb (cst:bbox pts)
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

;; plain TEXT at pt
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
                  (list 10 (car p) (cadr p) 0.0) (cons 40 r))))

;; Closed polyline through the points given, in order.
(defun cst:poly (pts lay / dxf p)
  (setq dxf (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 lay)
                  '(100 . "AcDbPolyline") (cons 90 (length pts)) '(70 . 1)))
  (foreach p pts
    (setq dxf (append dxf (list (cons 10 (cst:2d p))))))
  (entmakex dxf))

(defun cst:box (base w h lay)
  (cst:poly (list base
                  (cst:v+ base (list w 0.0))
                  (cst:v+ base (list w h))
                  (cst:v+ base (list 0.0 h)))
            lay))

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
  (cst:ensure-layer cst:*space-layer* 8)
  (cst:ensure-layer cst:*guide-layer* 4)
  (setq r   (cst:dotr w h)
        th  (cst:texth w h)
        i   0
        pts (cst:oval n w h)
        cst:*preview* (list (cst:box base w h cst:*space-layer*)))
  (foreach p pts
    (setq p   (cst:v+ base p)
          cst:*preview* (cons (cst:circle p r cst:*guide-layer*)
                              cst:*preview*)
          lab (cst:made (cst:text (list (+ (car p) r) (+ (cadr p) r))
                                  th (cst:letter i) cst:*guide-layer*))
          cst:*preview* (if lab (cons lab cst:*preview*) cst:*preview*)
          i   (1+ i)))
  (princ (strcat "\n  A to " (cst:letter (1- n))
                 " are shown clockwise from the top left, evenly spaced"))
  (princ "\n  round the space.  Where they really go is what the dims say.")
  (princ))

;; Safe to call at any time, including twice: an ename already gone has
;; no entget, and the list is emptied as it is swept.
(defun cst:unpreview ( / e)
  (foreach e cst:*preview* (if (and e (entget e)) (entdel e)))
  (setq cst:*preview* nil))

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
  (cond ((member v '("Back" "Undo")) 'CST-BACK)
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
  (cond ((member v '("Back" "Undo")) 'CST-BACK)
        ((null v) '(0.0 0.0))
        (t (cst:2d v))))

;; The two point letters in S, in any of the spellings an operator
;; types: "AC", "A-C", "a c", "A,C".  nil unless exactly two letters
;; land inside the run A..<n-1> and they differ.
(defun cst:parsepair (s n / i c ls k)
  (setq ls nil i 1)
  (repeat (strlen s)
    (setq c (substr s i 1)
          k (cst:index c))
    (if (not (null k)) (setq ls (cons k ls)))
    (setq i (1+ i)))
  (setq ls (reverse ls))
  (if (and (= 2 (length ls))
           (/= (car ls) (cadr ls))
           (< (car ls) n)
           (< (cadr ls) n))
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
  (setq s (cst:trim (getstring (strcat "\n  Pair to dimension <" dflt
                                       "> (B = back, D = done): "))))
  (cond ((= s "") (cst:parsepair dflt n))
        ((cst:back-word-p s) 'CST-BACK)
        ((member (strcase s) '("D" "DONE")) 'CST-DONE)
        ((cst:parsepair s n))
        (t (princ (strcat "\n    \"" s "\" is not a pair of these points -"
                          " two different letters"))
           (princ (strcat "\n    between A and " (cst:letter (1- n))
                          ", like " (cst:key 0 1) "."))
           (cst:askpair n dflt))))

(defun cst:charthelp (n order)
  (princ (strcat "\n\n  Cross dims.  " (itoa n) " points make "
                 (itoa (length order)) " possible pairs and not one of"))
  (princ "\n  them is compulsory - give the ones the sheet carries, in")
  (princ "\n  whatever order they are written down.")
  (princ "\n    Enter    takes the pair shown, so Enter over and over")
  (princ "\n             walks the whole chart in order")
  (princ "\n    A-C      jumps straight to that pair (AC and a c read too)")
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

;; The cross-dim chart.  Returns the chart, or CST-BACK when Back is
;; pressed with nothing in it yet.
(defun cst:askchart (n chart / order done nxt pr v k short cut)
  (setq order (cst:pairs n) done nil)
  (cst:charthelp n order)
  (while (not done)
    (setq nxt (cst:nextpair order chart))
    (if (null nxt)
      (progn (princ "\n  Every pair is given.")
             (setq pr 'CST-DONE))
      (setq pr (cst:askpair n nxt)))
    (cond
      ((eq pr 'CST-BACK)
       (if chart
         (progn
           (setq k     (car (car chart))
                 chart (cdr chart))
           (princ (strcat "\n    Stepping back one dimension - " k
                          " is blank again.")))
         (setq done T chart 'CST-BACK)))
      ((eq pr 'CST-DONE)
       (setq short (cst:thin n chart)
             cut   (if short nil (cst:cutoff n (cst:adjacency n chart))))
       (cond (short (cst:saythin short chart))
             (cut   (cst:saycut cut))
             (t     (setq done T))))
      (t
       (setq v (cst:askdist 'REQ (strcat "  " (cst:key (car pr) (cadr pr)))
                            nil T))
       (if (not (eq v 'CST-BACK))
         (progn
           (setq chart (cst:putdim (car pr) (cadr pr) v chart))
           (princ (strcat "\n    " (cst:key (car pr) (cadr pr)) " = "
                          (rtos v) "   (" (itoa (length chart)) " of "
                          (itoa (length order)) " given)")))))))
  chart)

;; The whole chain, with Back.  Returns (w h n base chart outline).
;; The first question offers no Back (STANDARDS section 3), so there is
;; no way out of here but forward or Esc -- and Esc lands in the
;; command's *error* handler, which sweeps the preview and closes the
;; undo group.
(defun cst:ask ( / step w h n base chart outline v)
  (setq step 1 chart nil outline T)
  (while (< step 7)
    (cond
      ((= step 1)
       (setq w (cst:askdist 'REQ "Space width (X)" nil nil)
             step 2))
      ((= step 2)
       (setq v (cst:askdist 'REQ "Space height (Y)" nil T))
       (if (eq v 'CST-BACK) (setq step 1) (setq h v step 3)))
      ((= step 3)
       (setq v (cst:askcount))
       (if (eq v 'CST-BACK) (setq step 2) (setq n v step 4)))
      ((= step 4)
       (setq v (cst:askbase))
       (if (eq v 'CST-BACK) (setq step 3) (setq base v step 5)))
      ((= step 5)
       (cst:preview n w h base)
       (setq v (cst:askchart n chart))
       (if (eq v 'CST-BACK)
         (progn (cst:unpreview) (setq step 4))
         (setq chart v step 6)))
      ((= step 6)
       (setq v (cst:askyn "Draw the outline through the points in order?"
                          "Yes" T))
       (if (eq v 'CST-BACK) (setq step 5) (setq outline v step 7)))))
  (list w h n base chart outline))

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
(defun cst:culprit (n w h chart bad / rest r)
  (setq rest (cst:deldim (car bad) chart))
  (if (and rest
           (null (cst:thin n rest))
           (null (cst:cutoff n (cst:adjacency n rest))))
    (progn
      (setq r (cadr (cst:worstdim (cst:solve n w h rest) rest)))
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
(defun cst:report (pts n w h base chart / order p k drawn off)
  (princ (strcat "\n\nCONSTELLATION " *constellation-version*))
  (princ (strcat "\n  Space   " (rtos w) " x " (rtos h)
                 ", base point " (rtos (car base)) "," (rtos (cadr base))))
  (princ (strcat "\n  Points  " (cst:namelist (cst:indices n))))
  (setq order (cst:pairs n))
  (princ (strcat "\n  Dims    " (itoa (length chart)) " given of "
                 (itoa (length order)) " possible"))
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

;;; ----------------------------------------------------------------------
;;;  The command
;;; ----------------------------------------------------------------------

(defun c:CONSTELLATION ( / *error* undo-open q w h n base chart
                           outline sol ref ang pts th i p wd worst
                           blame rms over cross)
  (defun *error* (msg)
    ;; user settings come back FIRST so nothing below can skip them
    (cst:sysrestore)
    ;; and the legend goes with them: a cancel part way through the
    ;; chart must not leave the starting oval in the drawing
    (cst:unpreview)
    (if undo-open (setq undo-open (cst:undoend)))
    (if (and msg (not (cst:error-cancel-p msg)))
      (princ (strcat "\nCONSTELLATION error: " msg)))
    (princ))
  (cst:syssave (cst:sysvars))
  (setvar "CMDECHO" 0)
  (setq undo-open (cst:undobegin))
  (cst:banner)
  (setq q       (cst:ask)
        w       (nth 0 q)
        h       (nth 1 q)
        n       (nth 2 q)
        base    (nth 3 q)
        chart   (nth 4 q)
        outline (nth 5 q))
  ;; the legend has done its job now that the real positions are coming
  (cst:unpreview)
  (princ "\n\n  Working the positions out...")
  ;; the shape the dims want, then the two things distances cannot say:
  ;; which way round (clockwise, as previewed) and which way up (turned
  ;; to sit in the space, and among the angles that do, nearest the oval)
  (setq sol (cst:unmirror (cst:centred (cst:solve n w h chart)))
        ref (cst:centred (cst:oval n w h))
        ang (cst:bestrot sol ref w h)
        pts (cst:place (cst:spin sol ang) base w h)
        th  (cst:texth w h))
  ;; ---- the drawing -----------------------------------------------------
  ;; colours only take on a layer this run has to CREATE; POINTS yellow
  ;; as XYPLOT and ABCDEF make it, DIMENSION yellow as POOL and SPA do
  (cst:ensure-layer cst:*space-layer* 8)
  (cst:ensure-layer cst:*point-layer* 2)
  (cst:ensure-layer cst:*dim-layer* 2)
  (cst:box base w h cst:*space-layer*)
  (cst:ensure-block)
  (setq i 0)
  (foreach p pts
    (cst:insert-pt p (cst:letter i) th)
    (setq i (1+ i)))
  (cst:drawdims pts n chart w h)
  (setq cross nil)
  (if outline
    (progn
      (cst:ensure-layer cst:*outline-layer* 3)
      (cst:poly pts cst:*outline-layer*)
      (setq cross (cst:crossing-p pts))))
  ;; ---- what it came out at ---------------------------------------------
  (cst:report pts n w h base chart)
  (setq wd    (cst:worstdim pts chart)
        worst (cadr wd)
        rms   (cst:rms pts chart)
        over  (cst:overflow pts w h)
        blame (if (> worst cst:*flag*) (cst:culprit n w h chart (car wd))))
  (princ (strcat "\n\n  Worst miss " (rtos worst) ", RMS " (rtos rms)
                 " over " (itoa (length chart))
                 (if (= 1 (length chart)) " dim." " dims.")))
  (if (> worst cst:*flag*)
    (progn
      (princ "\n  ** The starred dims cannot all be true at once.  The")
      (princ "\n  ** layout misses them by as little as anything can.")
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
        (princ "\n  ** Re-measure them before trusting it.")))
    (princ (strcat "\n  No dim missed by more than " (rtos cst:*flag*)
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
  (setq undo-open (cst:undoend))
  (cst:sysrestore)
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
