;;; ====================================================================
;;;  POOL.LSP -- Swimming-pool as-built layout tool
;;;
;;;  Command:  POOL
;;;
;;;  Draws a pool plan (Rectangle, Oval, Grecian, L or Lazy L) from
;;;  field measurements.
;;;
;;;  First asks whether the pool is IN-SQUARE or OUT-OF-SQUARE.  An
;;;  in-square pool is built true to the side/end measurements and no
;;;  cross dims (diagonals) are asked for or drawn.  An out-of-square
;;;  pool takes the full cross-dim route described below.
;;;
;;;  Rectangle corners may be Square, Rounded (radius) or Diag
;;;  (chamfer, sized by its face length).  Side lengths are always to
;;;  the TRUE corner; the treatment cuts inward.  In-square assumes all
;;;  four corners identical; out-of-square asks per corner (Enter
;;;  reuses the previous corner).  When corners are cut and the pool is
;;;  out-of-square, the cross dims are measured from one of: the true
;;;  Corner, the Middle of the cut/arc, or its Ends (both endpoints of
;;;  each diagonal).  Square corners -> cross dims from the true corner.
;;;
;;;  Out-of-square details:
;;;
;;;    * A gray nominal "guide" pool appears as soon as the shape is
;;;      chosen; while each measurement is prompted for, the matching
;;;      element of the guide turns red so you can see which dimension
;;;      is being asked for.  Once every dimension is in, the guide
;;;      deletes itself and is replaced by the true out-of-square pool.
;;;    * The full pool PERIMETER on layer POOL -- around the whole
;;;      shape including the Grecian corner cuts and oval end arcs
;;;      (drawn as individual lines/arcs, i.e. an exploded polyline).
;;;      Field measurements carry human error, so side lengths may be
;;;      held within +/-1" and cross dimensions within +/-2" of the
;;;      given values.
;;;    * Reference lines that are not part of the perimeter (the body
;;;      end lines under oval/Grecian ends, the oval radius
;;;      construction lines) go on POOL-NOTES with a DASHED linetype
;;;      (when acad.lin / acadiso.lin can be found).
;;;    * An exact as-measured two-triangle check (each triangle uses
;;;      one side, one end and the shared A-C cross dimension -- held
;;;      EXACTLY, no tolerance) is computed and reported as the
;;;      TRI CHECK B-D report row; the check figure itself is not
;;;      drawn, so out-of-square pools leave a clean drawing.
;;;    * Aligned dimensions for all sides and cross dims on layer
;;;      DIMENSION.  The two cross dims are drawn in the "CROSS
;;;      DIMENSION" dimension style when the drawing has one.
;;;    * A target / actual / delta report table to the right of the
;;;      drawing on POOL-NOTES.  When the cross dimensions cannot be
;;;      met within tolerance the sides are held true, the cross dims
;;;      get as close as possible, and "CROSS DIMS FAILED" is written
;;;      under the table.
;;;
;;;  Corner naming (plan view):   D ---------- C
;;;                               |            |     cross dims:
;;;                               |            |     A-C and B-D
;;;                               A ---------- B
;;;
;;;  Oval:    adds a radius line perpendicular to each end and a
;;;           three-point arc (end corner -> radius tip -> other end
;;;           corner) on both ends, plus a total-length check.
;;;  Grecian: 8-corner pool (body A/B/C/D plus angled-end tips
;;;           LT/LB left and RT/RB right).  Prompts for the six body
;;;           sides/ends, the four end diagonals and two end widths,
;;;           then cross dims at one of three detail levels:
;;;             Simple  = A-C, B-D            (2)
;;;             Center  = + LB-RT, LT-RB      (4, long tip-to-tip X)
;;;             Complex = every diagonal      (18, all pairs; NA any)
;;;           All 8 corners are best-fit against every provided cross
;;;           dim, so more cross dims pin the out-of-square shape down
;;;           more tightly.
;;;  L/LazyL: six-corner pools with one wing (square step joint for
;;;           the true L, angled joint for the lazy L); six sides plus
;;;           up to six cross dims, best-fit the same way.
;;;
;;;  Every cross-dim prompt also accepts NA when that measurement was
;;;  not taken in the field: the fitter skips it and the report shows
;;;  N/A for its target and delta.
;;;
;;;  Drawing units are assumed to be INCHES (tolerances: 1" sides,
;;;  2" cross dims, 1/2" max Grecian diagonal adjustment in 1/8"
;;;  steps).  Values may be typed in the current drawing units, e.g.
;;;  20'6-1/2" when units are set to Architectural.
;;;
;;;  Written in plain AutoLISP (entmake + classic commands, no
;;;  ActiveX/VLA), so it loads in AutoCAD 2018 as well as older
;;;  releases.
;;; ====================================================================

;;; -------------------- adjustable constants --------------------------

(setq pool:*side-tol*  1.0)     ; side length tolerance (drawing units)
(setq pool:*cross-tol* 2.0)     ; cross dimension tolerance
(setq pool:*grec-step* 0.125)   ; Grecian diagonal adjustment increment
(setq pool:*grec-max*  4)       ; max increments each way (4 * 1/8 = 1/2)
(setq pool:*base*      (list 0.0 0.0))
(setq pool:*dashlt*    "CONTINUOUS")  ; resolved to DASHED per run
(setq pool:*dotlt*     "CONTINUOUS")  ; resolved to POOLDOT per run
(setq pool:*lts*       1.0)           ; (legacy, unused: see pool:ltsc)
(setq pool:*mlkoff*    30.0)          ; M/L/K dim line offset right of the hopper
(setq pool:*pvents*    nil)           ; live guide-preview entities
(setq pool:*insq*      nil)           ; T = in-square pool (no cross dims)
;; Entities making up the side profile (section) and its depth dims.
;; An L pool's mirror flips the PLAN top-to-bottom; a longitudinal
;; section is unchanged by that, so these are held out of it.
(setq pool:*profents*  nil)

;; Bottom-type keywords, shared by the rectangle / oval / grecian
;; dispatchers.  Normal and the four special bottoms all run through
;; pool:hopnormal (they are the same plan chain with G and/or E
;; pinned); Sport is the symmetric full-width bottom.  L / Lazy L
;; pools take the standard hopper only and are not asked.
(setq pool:*btypes*   "Normal Sport Wedge SLope MOdflat SHallow")
(setq pool:*btshown* "Normal/Sport/Wedge/SLope/MOdflat/SHallow")
(setq pool:*sq4* (list (list "Square" 0.0) (list "Square" 0.0)
                       (list "Square" 0.0) (list "Square" 0.0)))
(setq pool:*valnotes* nil)            ; validation problems for the report
(setq pool:*undogrp*  nil)            ; an UNDO group of ours is open

;; Measurements under pool:*smalldim* are dimensioned in the drawing's
;; "STANDARD INCHES" dim style (see pool:dimsbegin); the missing-style
;; note is printed at most once per run.  Cross dims (the diagonal
;; block, any shape) use pool:*crossstyle* instead -- see pool:dimxbegin.
(setq pool:*smalldim*    24.0)
(setq pool:*smallstyle*  "STANDARD INCHES")
(setq pool:*smallwarned* nil)
(setq pool:*crossstyle*  "CROSS DIMENSIONS")
(setq pool:*dimstyle0*   nil)         ; dim style current when POOL started

;;; -------------------- small vector helpers --------------------------

(defun pool:d2r (a) (* pi (/ a 180.0)))

(defun pool:v+ (p q) (list (+ (car p) (car q)) (+ (cadr p) (cadr q))))

(defun pool:v- (p q) (list (- (car p) (car q)) (- (cadr p) (cadr q))))

(defun pool:v* (p s) (list (* (car p) s) (* (cadr p) s)))

(defun pool:dot (p q) (+ (* (car p) (car q)) (* (cadr p) (cadr q))))

(defun pool:perp (p) (list (- (cadr p)) (car p)))

(defun pool:mid (p q) (pool:v* (pool:v+ p q) 0.5))

(defun pool:unit (p / d)
  (setq d (sqrt (pool:dot p p)))
  (if (> d 1.0e-12) (pool:v* p (/ 1.0 d)) (list 0.0 0.0)))

;; local 2D point -> world 3D point (applies the insertion base)
(defun pool:wp (p)
  (list (+ (car p) (car pool:*base*))
        (+ (cadr p) (cadr pool:*base*))
        0.0))

;;; -------------------- geometry ---------------------------------------

;; Intersection of circle (c1 r1) with circle (c2 r2).
;; side = 1.0 -> point on the left of the c1->c2 direction, -1.0 -> right.
;; Returns a 2D point or nil when the circles do not intersect.
(defun pool:circint (c1 r1 c2 r2 side / d ux uy a h2 h bx by)
  (setq d (distance c1 c2))
  (if (> d 1.0e-9)
      (progn
        (setq ux (/ (- (car c2) (car c1)) d)
              uy (/ (- (cadr c2) (cadr c1)) d)
              a  (/ (+ (* d d) (* r1 r1) (- (* r2 r2))) (* 2.0 d))
              h2 (- (* r1 r1) (* a a)))
        (if (> h2 -1.0e-6)
            (progn
              (setq h  (sqrt (max h2 0.0))
                    bx (+ (car c1) (* a ux))
                    by (+ (cadr c1) (* a uy)))
              (list (+ bx (* side h (- uy)))
                    (+ by (* side h ux))))))))

;; Circumcenter of three points, or nil when collinear.
(defun pool:circum (p1 p2 p3 / ax ay bx by cx cy dd)
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

(defun pool:npos (a)
  (while (< a 0.0) (setq a (+ a pi pi)))
  (while (>= a (+ pi pi)) (setq a (- a pi pi)))
  a)

;;; -------------------- entity makers ----------------------------------

(defun pool:layer (name color)
  (if (not (tblsearch "LAYER" name))
      (entmake (list '(0 . "LAYER")
                     '(100 . "AcDbSymbolTableRecord")
                     '(100 . "AcDbLayerTableRecord")
                     (cons 2 name)
                     '(70 . 0)
                     (cons 62 color)
                     '(6 . "Continuous"))))
  name)

(defun pool:line (p1 p2 lay)
  (entmake (list '(0 . "LINE")
                 (cons 8 lay)
                 (cons 10 (pool:wp p1))
                 (cons 11 (pool:wp p2)))))

;; Build a linetype from an explicit pattern (positive = dash length,
;; 0 = dot, negative = gap), all in drawing units (inches).  Done with
;; entmake rather than loading acad.lin: a failed load used to fall
;; back to CONTINUOUS silently, which is why dashes could vanish.
;; Returns the linetype name.
(defun pool:ltmake (name descr pat / lst x)
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
;; pattern defined in inches always plots at that size no matter how
;; the host drawing is set up.
(defun pool:ltsc ( / s)
  (setq s (getvar "LTSCALE"))
  (if (or (null s) (<= s 0.0)) 1.0 (/ 1.0 s)))

;; Kept for compatibility: our patterns are self-defined now.
(defun pool:ltload (name)
  (if (= name "DOT")
      (pool:ltmake "POOLDOT" "Pool guide dot . . . . . . . ." '(0.0 -1.0))
      (pool:ltmake "POOLDASH" "Pool dashed __ __ __ __" '(12.0 -12.0))))

;; Dashed reference line on POOL-NOTES.
(defun pool:lined (p1 p2)
  (entmake (append (list '(0 . "LINE")
                         (cons 8 "POOL-NOTES")
                         (cons 10 (pool:wp p1))
                         (cons 11 (pool:wp p2)))
                   (if (/= pool:*dashlt* "CONTINUOUS")
                       (list (cons 6 pool:*dashlt*)
                             (cons 48 (pool:ltsc)))))))

;; Dotted WHITE guide line -- the cross dims and other measuring lines
;; on the input screen, so they read clearly over the pool outline.
(defun pool:linedot (p1 p2)
  (entmake (append (list '(0 . "LINE")
                         (cons 8 "POOL-NOTES")
                         (cons 62 pool:*pvx-col*)
                         (cons 10 (pool:wp p1))
                         (cons 11 (pool:wp p2)))
                   (if (/= pool:*dotlt* "CONTINUOUS")
                       (list (cons 6 pool:*dotlt*)
                             (cons 48 (pool:ltsc)))))))

(defun pool:text (pt h str lay)
  (entmake (list '(0 . "TEXT")
                 (cons 8 lay)
                 (cons 10 (pool:wp pt))
                 (cons 40 h)
                 (cons 1 str))))

(defun pool:textc (pt h str lay col)
  (entmake (list '(0 . "TEXT")
                 (cons 8 lay)
                 (cons 62 col)
                 (cons 10 (pool:wp pt))
                 (cons 40 h)
                 (cons 1 str))))

;; Three-point arc through p1 -> p2 -> p3 (falls back to a line when
;; the points are collinear).
(defun pool:arc3p (p1 p2 p3 lay / o r a1 a2 a3 da2 da3 s e)
  (setq o (pool:circum p1 p2 p3))
  (if o
      (progn
        (setq r  (distance o p1)
              a1 (angle o p1)
              a2 (angle o p2)
              a3 (angle o p3)
              da2 (pool:npos (- a2 a1))
              da3 (pool:npos (- a3 a1)))
        (if (< da2 da3)
            (setq s a1 e a3)
            (setq s a3 e a1))
        (entmake (list '(0 . "ARC")
                       (cons 8 lay)
                       (cons 10 (pool:wp o))
                       (cons 40 r)
                       (cons 50 s)
                       (cons 51 e))))
      (pool:line p1 p3 lay)))

;;; Small dimensions read in inches.  Any measurement under 24" is
;;; drawn in the "STANDARD INCHES" dim style when the drawing has one,
;;; and the previous style comes straight back afterwards.  Every
;;; dimension the routine draws goes through pool:dimalg / pool:dimrot
;;; / pool:dimrad / pool:dimcorner1, so switching in those four covers
;;; plan dims, hopper chain dims, corner treatments, radii and the
;;; side-profile depths alike.  (Angular corner dims measure degrees,
;;; not inches, so they are left alone.)

(defun pool:dimsbegin (d / odim)
  (if (< d pool:*smalldim*)
      (if (tblsearch "DIMSTYLE" pool:*smallstyle*)
          (progn
            (setq odim (getvar "DIMSTYLE"))
            ;; already current -> nothing to switch, nothing to undo
            (if (= (strcase odim) (strcase pool:*smallstyle*))
                (setq odim nil)
                (command "_.-DIMSTYLE" "_Restore" pool:*smallstyle*))
            odim)
          (progn
            (if (not pool:*smallwarned*)
                (progn
                  (princ (strcat "\n(no \"" pool:*smallstyle*
                                 "\" dim style in this drawing -- dims under "
                                 (rtos pool:*smalldim*)
                                 " drawn in the current style)"))
                  (setq pool:*smallwarned* t)))
            nil))))

(defun pool:dimsend (odim)
  (if (and odim (tblsearch "DIMSTYLE" odim))
      (command "_.-DIMSTYLE" "_Restore" odim)))

(defun pool:dimalg (p1 p2 pt / od)
  (setq od (pool:dimsbegin (distance p1 p2)))
  (command "_.DIMALIGNED" (pool:wp p1) (pool:wp p2) (pool:wp pt))
  (pool:dimsend od))

;; Radius dimension ON the arc, read from OUTSIDE it: the arc is picked
;; at its far point and the dimension line is dragged further out along
;; the same direction, so the leader comes in from outside instead of
;; running back to the circle centre.
(defun pool:dimrad (ent tip outd doff / od)
  (if (and ent (entget ent) (= "ARC" (cdr (assoc 0 (entget ent)))))
      (progn
        (setq od (pool:dimsbegin (cdr (assoc 40 (entget ent)))))
        (command "_.DIMRADIUS" (list ent (pool:wp tip))
                 (pool:wp (pool:v+ tip (pool:v* outd (* 0.9 doff)))))
        (pool:dimsend od))
      ;; a degenerate end (bulge ~ 0) drew a straight line instead
      (princ "\n(radius dim skipped -- the end came out flat, no arc)")))

;; Rotated linear dimension hooked to two OBJECT points: the ext-line
;; origins land on drawn geometry (wall endpoints / arc tangents), and
;; the rotation makes it read the full run regardless of the hooks.
(defun pool:dimrot (p1 p2 ang loc / od)
  ;; a rotated linear dim measures the RUN along ang, not p1->p2
  (setq od (pool:dimsbegin (abs (pool:dot (pool:v- p2 p1)
                                          (list (cos ang) (sin ang))))))
  (command "_.DIMLINEAR" (pool:wp p1) (pool:wp p2)
           "_R" (angtos ang 0 6) (pool:wp loc))
  (pool:dimsend od))

;; Switch to the CROSS DIMENSIONS dim style when the drawing has one.
;; Cross dims are drawn ByLayer (no per-entity color/linetype/lineweight
;; override) -- their look (dashed or otherwise) comes entirely from
;; that dim style and the DIMENSION layer, same as every other dim.
;; Returns the previous style name (for pool:dimxend), or nil.
(defun pool:dimxbegin ( / odim)
  (if (tblsearch "DIMSTYLE" pool:*crossstyle*)
      (progn
        (setq odim (getvar "DIMSTYLE"))
        (command "_.-DIMSTYLE" "_Restore" pool:*crossstyle*)
        odim)))

(defun pool:dimxend (odim)
  (if (and odim (tblsearch "DIMSTYLE" odim))
      (command "_.-DIMSTYLE" "_Restore" odim)))

;; Point offset outward (away from cen) from the midpoint of p->q.
;; A negative dist offsets inward instead.
(defun pool:outoff (p q cen dist / m n)
  (setq m (pool:mid p q)
        n (pool:unit (pool:perp (pool:v- q p))))
  (if (< (pool:dot (pool:v- m cen) n) 0.0)
      (setq n (pool:v* n -1.0)))
  (pool:v+ m (pool:v* n dist)))

;;; -------------------- user input -------------------------------------

;; The user's own object snaps stay LIVE during every measurement
;; prompt (typed input is unaffected; a picked point can snap onto
;; existing geometry).  OSMODE is zeroed only while the routine feeds
;; points to commands, where a snap would grab the wrong geometry.
(defun pool:osup ( / p)
  (setq p (assoc "OSMODE" pool:*sysold*))
  (if p (setvar "OSMODE" (cdr p))))

(defun pool:osdown () (setvar "OSMODE" 0))

(defun pool:ask (msg / v)
  (pool:osup)
  (initget 7)                           ; no null, no zero, no negative
  (setq v (getdist (strcat "\n" msg ": ")))
  (pool:osdown)
  v)

;;; -------------------- measurement sequences (Back) -------------------
;;;
;;;  A block of related measurements runs through pool:askseq so every
;;;  prompt after the first also offers *Back*, which re-asks the
;;;  previous question -- a typo no longer means Esc and start over.
;;;  Each item: (key kind msg ents dflt skip skipmsg)
;;;    key   symbol the answer is stored under
;;;    kind  REQ  a value is required
;;;          NAX  NA accepted (returns nil)
;;;          ZER  NA accepted, zero accepted
;;;          SUG  NA accepted, suggested default (Enter takes it)
;;;    ents  guide entities highlighted while prompted
;;;    dflt  for SUG: a number, or a list of keys -- the first of those
;;;          keys with a non-nil answer supplies the suggestion
;;;    skip  optional quoted expression; non-nil -> answered 0.0 unasked

(defun pool:sq (ans key) (cdr (assoc key ans)))

(defun pool:sqput (ans key v / out p)
  (foreach p ans (if (not (eq (car p) key)) (setq out (cons p out))))
  (reverse (cons (cons key v) out)))

(defun pool:sqfirst (ans keys / out k)
  (foreach k keys
    (if (and (not out) (pool:sq ans k)) (setq out (pool:sq ans k))))
  out)

;; One prompt of a sequence.  Returns the value, nil for NA, or the
;; symbol POOL-BACK.
(defun pool:asks (kind msg ents dflt back / v cols kw)
  (setq cols (mapcar 'pool:getcol ents))
  (foreach e ents (pool:setcol e pool:*hi-col*))
  (pool:osup)
  ;; Undo is accepted everywhere Back is, as a hidden synonym
  (setq kw (cond ((eq kind 'REQ) (if back "Back Undo" nil))
                 (back "NA Back Undo")
                 (t "NA")))
  (if kw
      ;; REQ always rejects zero (bit 7) - offering Back must not
      ;; loosen what counts as a valid measurement; ZER alone admits 0
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
  (pool:osdown)
  (mapcar '(lambda (e c) (pool:setcol e c)) ents cols)
  (cond ((and (= (type v) 'STR) (member v '("Back" "Undo"))) 'POOL-BACK)
        ((= (type v) 'STR) nil)               ; NA
        ((and (null v) (eq kind 'SUG)) dflt)  ; Enter took the suggestion
        (t v)))

;; Keyword question that can also be backed out of.  kws is the
;; initget string, shown is the bracketed list, dflt the Enter answer
;; (nil = an answer is required).  Returns the keyword or POOL-BACK.
(defun pool:askkw (msg kws shown dflt back / v)
  (initget (if dflt 0 (if back 0 1))
           (if back (strcat kws " Back Undo") kws))
  (setq v (getkword (strcat "\n" msg " [" shown
                            (if back "/Back" "") "]"
                            (if dflt (strcat " <" dflt ">") "") ": ")))
  (cond ((member v '("Back" "Undo")) 'POOL-BACK)
        ((null v) (if dflt dflt (pool:askkw msg kws shown dflt back)))
        (t v)))

;; Yes/No that can be backed out of.  Returns T, nil or POOL-BACK.
(defun pool:askyn (msg dflt back / v)
  (setq v (pool:askkw msg "Yes No" "Yes/No" dflt back))
  (if (eq v 'POOL-BACK) v (= v "Yes")))

;; Run a list of input stages with Back between them: a stage that
;; returns POOL-BACK sends the user to the previous stage, which is
;; re-asked from scratch.  Each stage is a function of no arguments
;; and must be safely re-runnable (it recomputes from its own answers).
;; Stage 1 has nowhere to go back to, so its Back is suppressed.
(defun pool:stages (fns / i n v)
  (setq i 0 n (length fns))
  (while (< i n)
    (setq v (apply (nth i fns) nil))
    (if (eq v 'POOL-BACK)
        ;; the first stage has nowhere to go back to, so it re-asks
        ;; rather than falling forward past its own question
        (if (> i 0) (setq i (1- i)))
        (setq i (1+ i))))
  (princ))

;; Run a whole block; returns the answers as an assoc list, or the
;; symbol POOL-BACK when the user backed out of its FIRST question
;; (only offered when bk is non-nil).
(defun pool:askseq (items / ans i n it v dflt asked)
  (setq ans (pool:askseqb items nil))
  ans)

(defun pool:askseqb (items bk / ans i n it v dflt asked out)
  (setq ans nil i 0 n (length items) asked nil out nil)
  (while (and (< i n) (not out))
    (setq it (nth i items))
    (if (and (nth 5 it) (eval (nth 5 it)))    ; auto-skip -> 0, unasked
        (progn
          (if (nth 6 it) (princ (nth 6 it)))
          (setq ans (pool:sqput ans (car it) 0.0)
                i (1+ i)))
        (progn
          (setq dflt (nth 4 it))
          (if (and dflt (listp dflt))
              (setq dflt (pool:sqfirst ans dflt)))
          (setq v (pool:asks (cadr it) (caddr it) (cadddr it) dflt
                             (if (or asked bk) t nil)))
          (if (eq v 'POOL-BACK)
              (if asked
                  (setq i (car asked) asked (cdr asked))
                  (setq out t))             ; backed out of the block
              (setq ans (pool:sqput ans (car it) v)
                    asked (cons i asked)
                    i (1+ i))))))
  (if out 'POOL-BACK ans))

;;; -------------------- guide preview ----------------------------------
;;; A gray nominal pool of the chosen shape is drawn as soon as the
;;; shape is picked.  While each measurement is prompted for, the
;;; matching element of the guide turns red so the user can see exactly
;;; which dimension is being asked for.  Once all inputs are in, the
;;; guide deletes itself and is replaced by the true out-of-square pool.

(setq pool:*pv-col* 8)                  ; guide outline color (dark gray)
(setq pool:*pvx-col* 7)                 ; cross-dim / measuring line color (white)
(setq pool:*hi-col* 1)                  ; highlight color (red)

;; Override (or set) the color of an entity, refresh it, return it.
(defun pool:setcol (e col / ed old)
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
(defun pool:getcol (e / ed)
  (if (and e (setq ed (entget e)) (assoc 62 ed))
      (cdr (assoc 62 ed))
      pool:*pv-col*))

;; Guide entities for a list of corner-label keys, e.g. '(lA lB), so a
;; prompt can light up the letters it names as well as the line.
(defun pool:lbl (pv keys / out k)
  (foreach k keys (setq out (append out (cdr (assoc k pv)))))
  out)

;; The guide's corner-label key for a letter string ("A" -> 'lA).
(defun pool:lblkey (s) (read (strcat "l" s)))

(defun pool:pvline (p1 p2)
  (pool:line p1 p2 "POOL-NOTES")
  (pool:setcol (entlast) pool:*pv-col*))

;; Guide measuring line -- the cross dims and other ties, drawn WHITE
;; and DOTTED so they stand out from the gray pool outline.
(defun pool:pvlined (p1 p2)
  (pool:linedot p1 p2)
  (entlast))

;; Ask for a distance while the matching guide elements glow red, then
;; restore each element to the color it had (outline vs cross-dim gray).
(defun pool:askh (msg ents / v cols)
  (setq cols (mapcar 'pool:getcol ents))
  (foreach e ents (pool:setcol e pool:*hi-col*))
  (setq v (pool:ask msg))
  (mapcar '(lambda (e c) (pool:setcol e c)) ents cols)
  v)

;; Delete all guide entities (tracked globally so the *error* handler
;; can clean up after a cancel mid-prompt).
(defun pool:pvkill ()
  (foreach e pool:*pvents*
    (if (and e (entget e)) (entdel e)))
  (setq pool:*pvents* nil))

;; Remove an item (by equality) from a list.
(defun pool:lremove (x lst / out i)
  (foreach i lst (if (not (equal i x)) (setq out (cons i out))))
  (reverse out))

;; Track a freshly made guide entity so pool:pvkill / *error* find it.
(defun pool:pvadd (e)
  (setq pool:*pvents* (cons e pool:*pvents*))
  e)

;; Delete specific guide entities mid-flow and untrack them (used when
;; part of the guide is redrawn, e.g. corner treatments).
(defun pool:pvdel (ents / e)
  (foreach e ents
    (if (and e (entget e)) (entdel e))
    (setq pool:*pvents* (pool:lremove e pool:*pvents*))))

;; Mirror everything drawn after `after` about the HORIZONTAL line
;; y = y0 -- a top-to-bottom flip.
;;
;; L and Lazy L pools flip this way rather than left-to-right, because
;; the deep end is always the end AWAY from the wing: flipping
;; left-to-right would swing the wing across and carry the hopper over
;; to the right-hand side of the sheet with it.  Flipping top-to-bottom
;; swaps which way the wing points instead and leaves the deep end --
;; and so the hopper -- on the left, where the convention wants it.
;;
;; The side profile is held out of it (pool:*profents*): that is a
;; LONGITUDINAL section, and turning the plan upside down does not
;; change it.  Text is mirrored with MIRRTEXT off so it stays readable.
(defun pool:mirrory (after y0 / ss e mt)
  (setq ss (ssadd)
        e (if after (entnext after) (entnext)))
  (while e
    (if (not (member e pool:*profents*)) (ssadd e ss))
    (setq e (entnext e)))
  (if (> (sslength ss) 0)
      (progn
        (setq mt (getvar "MIRRTEXT"))
        (setvar "MIRRTEXT" 0)
        (command "_.MIRROR" ss "" (list 0.0 y0 0.0) (list 1.0 y0 0.0) "_Y")
        (setvar "MIRRTEXT" mt)))
  (princ))

;; Draw the nominal guide pool for the chosen shape (fixed 360 x 180
;; body).  Returns an assoc list mapping each input key to the list of
;; guide entities to highlight, plus an ALL entry with every guide
;; entity for later deletion.
(defun pool:preview (ptype / pw ph a b c d cen pr all pv ent
                             eab ebc ecd eda
                             midl midr tipl tipr elrad errad elarc erarc etot)
  (setq pw 360.0 ph 180.0
        a (list 0.0 0.0) b (list pw 0.0) c (list pw ph) d (list 0.0 ph)
        cen (list (* 0.5 pw) (* 0.5 ph))
        eab (pool:pvline a b)
        ebc (pool:pvline b c)
        ecd (pool:pvline d c)
        eda (pool:pvline d a)
        all (list eab ebc ecd eda)
        pv (list (cons 'ab (list eab)) (cons 'bc (list ebc))
                 (cons 'dc (list ecd)) (cons 'da (list eda))))
  ;; No body diagonals here: the cross dims only appear once every side
  ;; length is in, one guide line per measurement (see pool:quadflow).
  (foreach pr (list (list a "A") (list b "B") (list c "C") (list d "D"))
    (pool:text (pool:v+ (car pr)
                        (pool:v* (pool:unit (pool:v- (car pr) cen)) 20.0))
               12.0 (cadr pr) "POOL-NOTES")
    (setq ent (pool:setcol (entlast) pool:*pv-col*)
          all (cons ent all)
          pv (cons (cons (pool:lblkey (cadr pr)) (list ent)) pv)))
  (cond
    ((= ptype "Oval")
     ;; the guide's radius lines run from each end arc's CENTRE to its
     ;; tip, so they read as the true radius that is being asked for
     (setq midl (list 0.0 (* 0.5 ph)) tipl (list -80.0 (* 0.5 ph))
           midr (list pw (* 0.5 ph)) tipr (list (+ pw 80.0) (* 0.5 ph))
           elrad (pool:pvlined (pool:circum a tipl d) tipl)
           errad (pool:pvlined (pool:circum b tipr c) tipr))
     (pool:arc3p a tipl d "POOL-NOTES")
     (setq elarc (pool:setcol (entlast) pool:*pv-col*))
     (pool:arc3p b tipr c "POOL-NOTES")
     (setq erarc (pool:setcol (entlast) pool:*pv-col*))
     (setq etot (pool:pvlined tipl tipr)
           all (append all (list elrad errad elarc erarc etot))
           pv (append pv (list (cons 'lrad (list elrad elarc))
                               (cons 'rrad (list errad erarc))
                               (cons 'tot (list etot)))))))
  (setq pool:*pvents* all)
  pv)

;;; -------------------- quadrilateral fitting --------------------------

;; Measured lengths of quad (A B C D):
;; (bottom top left right crossAC crossBD)
(defun pool:quadmeas (q / a b c d)
  (setq a (car q) b (cadr q) c (caddr q) d (cadddr q))
  (list (distance a b) (distance d c) (distance a d) (distance b c)
        (distance a c) (distance b d)))

;; Cross-dim error of a quad; a nil target (NA) contributes nothing.
(defun pool:diagerr (q dac dbd / e1 e2)
  (setq e1 (if dac (- (distance (car q) (caddr q)) dac) 0.0)
        e2 (if dbd (- (distance (cadr q) (cadddr q)) dbd) 0.0))
  (+ (* e1 e1) (* e2 e2)))

;; Quad with all four sides EXACT, parameterised by the interior angle
;; at corner A (four-bar linkage).  Returns (A B C D) or nil.
(defun pool:4bar (bo tp le ri alfa / a b d c1 c2)
  (setq a (list 0.0 0.0)
        b (list bo 0.0)
        d (list (* le (cos alfa)) (* le (sin alfa)))
        c1 (pool:circint b ri d tp 1.0)
        c2 (pool:circint b ri d tp -1.0))
  (cond
    ((and c1 c2)
     (list a b (if (> (distance a c1) (distance a c2)) c1 c2) d))
    (c1 (list a b c1 d))
    (c2 (list a b c2 d))
    (t nil)))

;; Scan the angle at A over [a0 a1], returning (quad alfa) with the
;; smallest cross-dim error, or nil.
(defun pool:scanalfa (bo tp le ri dac dbd a0 a1 step / alfa q e best bestq)
  (setq alfa a0 best 1.0e30 bestq nil)
  (while (<= alfa a1)
    (setq q (pool:4bar bo tp le ri alfa))
    (if q
        (progn
          (setq e (pool:diagerr q dac dbd))
          (if (< e best) (setq best e bestq (list q alfa)))))
    (setq alfa (+ alfa step)))
  bestq)

;; Best quad with sides held EXACTLY true, cross dims as close as
;; possible.  Coarse scan then fine refine.  Returns quad or nil.
;; With both cross dims NA there is nothing to skew for: square up.
(defun pool:fitsides (bo tp le ri dac dbd / r1 r2 alfa)
  (if (and (null dac) (null dbd))
      (pool:4bar bo tp le ri (pool:d2r 90.0))
      (progn
        (setq r1 (pool:scanalfa bo tp le ri dac dbd
                                (pool:d2r 15.0) (pool:d2r 165.0) (pool:d2r 0.25)))
        (if r1
            (progn
              (setq alfa (cadr r1)
                    r2 (pool:scanalfa bo tp le ri dac dbd
                                      (- alfa (pool:d2r 0.3)) (+ alfa (pool:d2r 0.3))
                                      (pool:d2r 0.005)))
              (car (if r2 r2 r1)))))))

(defun pool:setnth (lst i val / k out)
  (setq k 0 out nil)
  (foreach x lst
    (setq out (cons (if (= k i) val x) out)
          k (1+ k)))
  (reverse out))

;; One distance-constraint relaxation step: pull points i and j of pts
;; so their distance moves into [lo hi] (lo = hi -> exact pull).
(defun pool:relax1 (pts i j lo hi w / p q d des err ux uy e2)
  (setq p (nth i pts)
        q (nth j pts)
        d (distance p q))
  (if (> d 1.0e-9)
      (progn
        (setq des (min (max d lo) hi)
              err (- d des))
        (if (/= err 0.0)
            (progn
              (setq ux (/ (- (car q) (car p)) d)
                    uy (/ (- (cadr q) (cadr p)) d)
                    e2 (* 0.5 w err))
              (setq pts (pool:setnth pts i
                          (list (+ (car p) (* e2 ux)) (+ (cadr p) (* e2 uy)))))
              (setq pts (pool:setnth pts j
                          (list (- (car q) (* e2 ux)) (- (cadr q) (* e2 uy)))))))))
  pts)

(defun pool:rot (p ang)
  (list (- (* (car p) (cos ang)) (* (cadr p) (sin ang)))
        (+ (* (car p) (sin ang)) (* (cadr p) (cos ang)))))

;; Re-gauge a polygon: first point at the origin, second on the +X
;; axis, bulk of the shape above the axis.  Works for any point count.
(defun pool:normpoly (pts / a ang my)
  (setq a (car pts)
        pts (mapcar '(lambda (p) (pool:v- p a)) pts)
        ang (- (angle (list 0.0 0.0) (cadr pts)))
        pts (mapcar '(lambda (p) (pool:rot p ang)) pts)
        my 0.0)
  (foreach a pts (setq my (+ my (cadr a))))
  (if (< my 0.0)
      (setq pts (mapcar '(lambda (p) (list (car p) (- (cadr p)))) pts)))
  pts)

;; Iterative relaxation of an arbitrary point list against distance
;; constraints (i j lo hi weight); lo = hi -> exact pull.
(defun pool:relaxn (pts conlst niter / k c)
  (setq k 0)
  (while (< k niter)
    (foreach c conlst
      (setq pts (pool:relax1 pts (car c) (cadr c) (caddr c) (cadddr c) (nth 4 c))))
    (setq k (1+ k)))
  (pool:normpoly pts))

;; Quad relaxation: sides banded to +/-stol, provided cross dims
;; pulled to their exact targets.  Cross dims pull first, side bands
;; clamp last so each sweep ends with the sides inside their band.
(defun pool:relaxquad (pts bo tp le ri dac dbd stol niter / conlst)
  (setq conlst nil)
  (if dbd (setq conlst (cons (list 1 3 dbd dbd 0.5) conlst)))
  (if dac (setq conlst (cons (list 0 2 dac dac 0.5) conlst)))
  (setq conlst (append conlst
                       (list (list 0 1 (- bo stol) (+ bo stol) 1.0)
                             (list 3 2 (- tp stol) (+ tp stol) 1.0)
                             (list 0 3 (- le stol) (+ le stol) 1.0)
                             (list 1 2 (- ri stol) (+ ri stol) 1.0))))
  (pool:relaxn pts conlst niter))

;; Fit the parametric quad.  Returns (quad failedflag):
;;  1. hold sides exact, pick the angle whose cross dims are closest;
;;     if both cross dims land inside xtol -> done, no failure.
;;  2. otherwise let the sides flex inside +/-stol and pull the cross
;;     dims to their targets; if everything then fits -> done.
;;  3. otherwise: sides held true (result of step 1), cross dims as
;;     close as possible, failure flag set.
(defun pool:fitquad (bo tp le ri dac dbd stol xtol / q1 m1 q2 m2 sok xok)
  (setq q1 (pool:fitsides bo tp le ri dac dbd))
  (if (null q1)                         ; degenerate input fallback
      (setq q1 (list (list 0.0 0.0) (list bo 0.0)
                     (list bo (* 0.5 (+ le ri))) (list 0.0 le))))
  (setq m1 (pool:quadmeas q1))
  (if (and (or (null dac) (<= (abs (- (nth 4 m1) dac)) xtol))
           (or (null dbd) (<= (abs (- (nth 5 m1) dbd)) xtol)))
      (list q1 nil)
      (progn
        (setq q2 (pool:relaxquad q1 bo tp le ri dac dbd stol 2000)
              m2 (pool:quadmeas q2)
              sok (and (<= (abs (- (car m2) bo)) (+ stol 0.05))
                       (<= (abs (- (cadr m2) tp)) (+ stol 0.05))
                       (<= (abs (- (caddr m2) le)) (+ stol 0.05))
                       (<= (abs (- (cadddr m2) ri)) (+ stol 0.05)))
              xok (and (or (null dac) (<= (abs (- (nth 4 m2) dac)) (+ xtol 0.05)))
                       (or (null dbd) (<= (abs (- (nth 5 m2) dbd)) (+ xtol 0.05)))))
        (if (and sok xok)
            (list q2 nil)
            (list q1 t)))))

;; Exact two-triangle check (report only, nothing is drawn from it):
;;   triangle 1 = A B C  (bottom side, right end, cross A-C)
;;   triangle 2 = A C D  (top side, left end, shared cross A-C)
;; All lengths held exactly.  Returns (A B C D) or nil when the given
;; lengths cannot form the triangles.
(defun pool:triquad (bo tp le ri dac / a b c d)
  (setq a (list 0.0 0.0)
        b (list bo 0.0)
        c (pool:circint a dac b ri 1.0))
  (if c (setq d (pool:circint a le c tp 1.0)))
  (if (and c d) (list a b c d)))

;;; -------------------- grecian ends -----------------------------------

;; Distance between the two diagonal end points for end width w,
;; diagonal lengths lt/lb and diagonal angle th (from the end line's
;; outward normal).
(defun pool:grecf (w lt lb th)
  (sqrt (+ (expt (- w (* (+ lt lb) (sin th))) 2)
           (expt (* (- lt lb) (cos th)) 2))))

;; Best diagonal angle for target end width e: scan 1..89 degrees.
;; Returns (theta err).
(defun pool:grecth (w lt lb e / th best berr dd)
  (setq th 0.0175 best 0.7854 berr 1.0e30)
  (while (< th 1.5533)
    (setq dd (abs (- (pool:grecf w lt lb th) e)))
    (if (< dd berr) (setq berr dd best th))
    (setq th (+ th 0.00087)))           ; ~ 0.05 degree steps
  (list best berr))

;; Try to fit the end width by adjusting the angle; when that is not
;; enough, adjust the diagonal lengths in 1/8" increments (smallest
;; total adjustment first) up to +/-1/2".
;; Returns (ltUsed lbUsed theta) or nil.
(defun pool:grecfit (w lt lb e / s i j lt2 lb2 r out n)
  (setq n pool:*grec-max* s 0 out nil)
  (while (and (null out) (<= s (* 2 n)))
    (setq i (- n))
    (while (and (null out) (<= i n))
      (setq j (- n))
      (while (and (null out) (<= j n))
        (if (= (+ (abs i) (abs j)) s)
            (progn
              (setq lt2 (+ lt (* pool:*grec-step* i))
                    lb2 (+ lb (* pool:*grec-step* j)))
              (if (and (> lt2 0.0) (> lb2 0.0))
                  (progn
                    (setq r (pool:grecth w lt2 lb2 e))
                    (if (<= (cadr r) 0.0625)   ; within 1/16"
                        (setq out (list lt2 lb2 (car r))))))))
        (setq j (1+ j)))
      (setq i (1+ i)))
    (setq s (1+ s)))
  out)

;; Compute one Grecian end (no drawing).  pbot/ptop = end line
;; corners, mdir = unit normal pointing away from the pool body.
;; Returns (p1 p2 ltUsed lbUsed theta okflag); p1 joins ptop, p2 joins
;; pbot.  When the fit fails the end falls back to 45 degrees with the
;; given lengths, okflag nil.
(defun pool:grecendp (pbot ptop mdir lt lb e / u fit lt2 lb2 th ok dtop dbot)
  (setq u (pool:unit (pool:v- ptop pbot))
        fit (pool:grecfit (distance pbot ptop) lt lb e))
  (if fit
      (setq lt2 (car fit) lb2 (cadr fit) th (caddr fit) ok t)
      (setq lt2 lt lb2 lb th (pool:d2r 45.0) ok nil))
  (setq dtop (pool:v- (pool:v* mdir (cos th)) (pool:v* u (sin th)))
        dbot (pool:v+ (pool:v* mdir (cos th)) (pool:v* u (sin th))))
  (list (pool:v+ ptop (pool:v* dtop lt2))
        (pool:v+ pbot (pool:v* dbot lb2))
        lt2 lb2 th ok))

;;; -------------------- grecian cross-dim modes -------------------------
;;;
;;;  A Grecian pool has 8 corners; from the bottom-left, clockwise:
;;;
;;;         D ------------------ C          body:  A B C D
;;;        /                      \         left tips:  LT (off D), LB (off A)
;;;      LT                        RT       right tips: RT (off C), RB (off B)
;;;        \                      /
;;;         LB                  RB          index order used below:
;;;           \                /             0=A 1=B 2=RB 3=RT 4=C 5=D 6=LT 7=LB
;;;            A ------------ B
;;;
;;;  Cross-dim modes (how many diagonals the user is asked for):
;;;    Simple  = A-C, B-D                       (2, the body diagonals)
;;;    Center  = Simple + LB-RT, LT-RB          (4, adds the long tip X)
;;;    Complex = every possible diagonal        (18, all pairs; NA any)
;;;  More provided cross dims -> the out-of-square shape is pinned down
;;;  more tightly.  Any cross dim may be answered NA.

(setq pool:*grecnames*
      (list "A" "B" "RB" "RT" "C" "D" "LT" "LB"))

;; perimeter edges + the two body-end chords as (i j prompt-key band):
;; body sides loose (1"), end diagonals held near the given 1/2", end
;; widths near-exact.  The prompt-key ties each edge to its guide
;; highlight and prompt.
(setq pool:*grecedges*
      (list '(0 1 ab  1.0)     ; A-B  bottom side
            '(1 2 rbd 0.5)     ; B-RB right diag bottom
            '(2 3 rew 0.1)     ; RB-RT right end width
            '(3 4 rtd 0.5)     ; RT-C right diag top
            '(4 5 cd  1.0)     ; C-D  top side
            '(5 6 ltd 0.5)     ; D-LT left diag top
            '(6 7 lew 0.1)     ; LT-LB left end width
            '(7 0 lbd 0.5)     ; LB-A left diag bottom
            '(0 5 ad  1.0)     ; A-D  left end (internal chord)
            '(1 4 bc  1.0)))   ; B-C  right end (internal chord)

(setq pool:*grec-simple*
      (list '(0 4 "A-C") '(1 5 "B-D")))
(setq pool:*grec-center*
      (list '(0 4 "A-C") '(1 5 "B-D") '(7 3 "LB-RT") '(6 2 "LT-RB")
            ;; tip to tip along the top and along the bottom -- the two
            ;; tapes a crew can run straight down the pool's own edges
            '(6 3 "LT-RT") '(7 2 "LB-RB")
            ;; the X over each end cut (tip to the near body corner)...
            '(5 7 "D-LB") '(0 6 "A-LT")
            '(2 4 "RB-C") '(1 3 "B-RT")
            ;; ...and each tip to the far bottom/top body corner
            '(1 6 "B-LT") '(4 7 "C-LB")
            '(0 3 "A-RT") '(2 5 "RB-D")))
(setq pool:*grec-complex*
      (list '(0 2 "A-RB") '(0 3 "A-RT") '(0 4 "A-C")  '(0 6 "A-LT")
            '(1 3 "B-RT") '(1 5 "B-D")  '(1 6 "B-LT") '(1 7 "B-LB")
            '(2 4 "RB-C") '(2 5 "RB-D") '(2 6 "RB-LT") '(2 7 "RB-LB")
            '(3 5 "RT-D") '(3 6 "RT-LT") '(3 7 "RT-LB")
            '(4 6 "C-LT") '(4 7 "C-LB")
            '(5 7 "D-LB")))

(defun pool:grecmode (m)
  (cond ((= m "Center")  pool:*grec-center*)
        ((= m "Complex") pool:*grec-complex*)
        (t               pool:*grec-simple*)))

;; Worst cross-dim miss over the provided (non-nil) targets.
(defun pool:crossmax (pts crosscons / mx d)
  (setq mx 0.0)
  (foreach c crosscons
    (if (caddr c)
        (setq d (abs (- (distance (nth (car c) pts) (nth (cadr c) pts)) (caddr c)))
              mx (max mx d))))
  mx)

;; Worst amount any edge sits OUTSIDE its band (<=0 means all in band).
(defun pool:edgemax (pts edgecons / mx d)
  (setq mx -1.0e30)
  (foreach e edgecons
    (setq d (- (abs (- (distance (nth (car e) pts) (nth (cadr e) pts)) (caddr e)))
               (cadddr e))
          mx (max mx d)))
  mx)

;; Generic two-phase best fit of a point list:
;;   edgecons  = (i j target band)   crosscons = (i j target)
;;   1. pull crosses while holding edges EXACT; if crosses land inside
;;      xtol -> done, no failure.
;;   2. let edges flex within their bands and pull crosses; if edges
;;      stay in band and crosses land inside xtol -> done.
;;   3. otherwise edges held true (step-1 result), crosses as close as
;;      possible, failure flag set.
;; Returns (pts failed).
(defun pool:fitpoly (seed edgecons crosscons xtol / xcon e0 eb p1 p2)
  (setq xcon nil)
  (foreach c crosscons                  ; provided (non-NA) crosses only
    (if (caddr c)
        (setq xcon (cons (list (car c) (cadr c) (caddr c) (caddr c) 0.5) xcon))))
  (setq e0 (mapcar '(lambda (e) (list (car e) (cadr e) (caddr e) (caddr e) 1.0))
                   edgecons)
        eb (mapcar '(lambda (e) (list (car e) (cadr e)
                                      (- (caddr e) (cadddr e))
                                      (+ (caddr e) (cadddr e)) 1.0))
                   edgecons))
  (setq p1 (pool:relaxn seed (append xcon e0) 3000)
        p1 (pool:relaxn p1 e0 400))
  (if (<= (pool:crossmax p1 crosscons) xtol)
      (list p1 nil)
      (progn
        (setq p2 (pool:relaxn p1 (append xcon eb) 3000))
        (if (and (<= (pool:edgemax p2 edgecons) 0.05)
                 (<= (pool:crossmax p2 crosscons) (+ xtol 0.05)))
            (list p2 nil)
            (list p1 t)))))

;; The tip-to-tip widths LT-RT and LB-RB, in either corner order.
(defun pool:tippair (i j)
  (or (and (= i 6) (= j 3)) (and (= i 3) (= j 6))
      (and (= i 7) (= j 2)) (and (= i 2) (= j 7))))

;; Look up a provided cross target for corner pair (i j); nil if NA or
;; not in the active set.
(defun pool:crossget (crosscons i j / out)
  (foreach c crosscons
    (if (or (and (= (car c) i) (= (cadr c) j))
            (and (= (car c) j) (= (cadr c) i)))
        (setq out (caddr c))))
  out)

(defun pool:grecnm (i j)
  (strcat (nth i pool:*grecnames*) "-" (nth j pool:*grecnames*)))

;; Gray guide for a Grecian: 8-corner nominal body (solid perimeter,
;; dashed internal end chords), corner labels clear of the linework,
;; and the active mode's cross diagonals (dashed).  Returns the
;; highlight assoc (edge prompt-keys + one entry per cross name).
(setq pool:*grecnpts* (list (list 0.0 0.0) (list 360.0 0.0) (list 410.0 55.0)
                            (list 410.0 125.0) (list 360.0 180.0)
                            (list 0.0 180.0) (list -50.0 125.0)
                            (list -50.0 55.0)))

;; An OCTAGON is the same eight-corner shape with the same edge list --
;; only the proportions differ: its cuts run at 45 degrees (S = S1) and
;; its short flats match the cut faces, where a grecian's ends are long
;; and shallow.
;;
;; The guide is a REGULAR octagon -- 300 square, cut c = 300/(2+root 2)
;; = 87.87, so all eight sides come out 124.26 -- because that is what
;; the shape being measured looks like.  (An elongated guide made the
;; sheet read like a grecian's.)
(setq pool:*octnpts* (list (list 87.87 0.0) (list 212.13 0.0)
                           (list 300.0 87.87) (list 300.0 212.13)
                           (list 212.13 300.0) (list 87.87 300.0)
                           (list 0.0 212.13) (list 0.0 87.87)))

(defun pool:grecpreview (crosses npts / cen p q e c ent all pv k)
  (setq cen (list 0.0 0.0) all nil pv nil)
  (foreach p npts (setq cen (pool:v+ cen p)))
  (setq cen (pool:v* cen (/ 1.0 8.0)))
  (foreach e pool:*grecedges*
    (setq p (nth (car e) npts) q (nth (cadr e) npts)
          ent (if (member (caddr e) '(ad bc)) (pool:pvlined p q) (pool:pvline p q))
          pv (cons (cons (caddr e) (list ent)) pv)
          all (cons ent all)))
  ;; crosses is normally nil here: pool:greccross adds the chosen
  ;; mode's diagonals once the perimeter is measured
  (foreach c crosses
    (setq ent (pool:pvlined (nth (car c) npts) (nth (cadr c) npts))
          pv (cons (cons (caddr c) (list ent)) pv)
          all (cons ent all)))
  (setq k 0)
  (foreach p npts
    (pool:text (pool:lbloff p cen npts 22.0) 12.0 (nth k pool:*grecnames*) "POOL-NOTES")
    (setq ent (pool:setcol (entlast) pool:*pv-col*)
          all (cons ent all)
          pv (cons (cons (pool:lblkey (nth k pool:*grecnames*)) (list ent)) pv)
          k (1+ k)))
  (setq pool:*pvents* all)
  pv)

;; Add the chosen mode's cross diagonals to the Grecian guide once the
;; perimeter is measured.  Returns the extended highlight assoc.
(defun pool:greccross (crosses pv npts / c ent)
  (foreach c crosses
    (setq ent (pool:pvadd (pool:pvlined (nth (car c) npts) (nth (cadr c) npts)))
          pv (cons (cons (caddr c) (list ent)) pv)))
  pv)

;; Full guided flow for a Grecian pool (all three cross-dim modes).
;; Caller handles sysvars / undo / zoom-extents.
;; Resolve the overall-sheet letters against the overalls: S/T close
;; against B (T absorbs any difference), S1/V against A (V absorbs);
;; NA entries are derived, and with a whole pair NA a nominal split is
;; used.  Returns (S T S1 V).
;; WALLS BEAT CORNERS.  T and V run along a wall, so a tape can be
;; held flat against them and they come back reliable.  S and S1 only
;; locate the VIRTUAL sharp corner out past the cut -- on a real pool
;; there is nothing there to measure to, so they are the softer
;; numbers.  When both are given, the wall wins and its partner is
;; re-derived from the overall (S = (B - T)/2, S1 = (A - V)/2); the
;; taped S / S1 still show in the report against what was drawn.
;; Only when the wall was NOT measured does S / S1 drive the shape.
(defun pool:grecov (aov bov sraw traw s1raw vraw / s tv s1 v)
  (cond
    (traw (setq s (/ (- bov traw) 2.0) tv traw))
    (sraw (setq s sraw tv (- bov (* 2.0 sraw))))
    (t (setq s (/ bov 8.0) tv (* 0.75 bov))))
  (cond
    (vraw (setq s1 (/ (- aov vraw) 2.0) v vraw))
    (s1raw (setq s1 s1raw v (- aov (* 2.0 s1raw))))
    (t (setq s1 (/ aov 6.0) v (* aov (/ 2.0 3.0)))))
  (list s tv s1 v))

;; Octagon overall sheet.  With the letters unmeasured the shape is
;; derived from A and B alone, per the sheet: the four corners are cut
;; at 45 degrees (so S = S1 = c) and the SHORT flats equal the cut
;; faces, i.e. every side of a square octagon is the same length.
;;   c = min(A,B) / (2 + sqrt 2)   ->   T = B - 2c,  V = A - 2c
;; A measured letter wins over the derivation, and -- exactly like the
;; grecian sheet -- the WALL letters (T, V) win over the corner ones
;; (S, S1) when both were taped.  Returns (S T S1 V).
(defun pool:octov (aov bov sraw traw s1raw vraw / c s tv s1 v)
  (setq c (/ (min aov bov) 3.41421356237))
  (cond
    (traw (setq s (/ (- bov traw) 2.0) tv traw))
    (sraw (setq s sraw tv (- bov (* 2.0 sraw))))
    (t (setq s c tv (- bov (* 2.0 c)))))
  (cond
    (vraw (setq s1 (/ (- aov vraw) 2.0) v vraw))
    (s1raw (setq s1 s1raw v (- aov (* 2.0 s1raw))))
    ;; an unmeasured vertical cut matches the horizontal one (45 deg)
    (t (setq s1 s v (- aov (* 2.0 s)))))
  (list s tv s1 v))

;; Overall-sheet guide ties (B T S A S1 V S2) laid around the nominal
;; guide like the field sheet.  Returns the highlight assoc.
(defun pool:grecovties (oct / pv)
  ;; laid around the regular octagon: B/T/S across the top, A/S1/V
  ;; down the left, S2 parallel to the bottom-right cut
  (if oct
      (setq pv (list
        (pool:pvtie (list 0.0 360.0) (list 300.0 360.0) "B" 10.0)
        (pool:pvtie (list 87.87 335.0) (list 212.13 335.0) "T" 10.0)
        (pool:pvtie (list 0.0 335.0) (list 87.87 335.0) "S" 10.0)
        (pool:pvtie (list -95.0 0.0) (list -95.0 300.0) "A" 10.0)
        (pool:pvtie (list -45.0 212.13) (list -45.0 300.0) "S1" 10.0)
        (pool:pvtie (list -45.0 87.87) (list -45.0 212.13) "V" 10.0)
        (pool:pvtie (list 230.0 -17.9) (list 317.9 70.0) "S2" 10.0)))
      (setq pv (list
        (pool:pvtie (list -50.0 240.0) (list 410.0 240.0) "B" 10.0)
        (pool:pvtie (list 0.0 215.0) (list 360.0 215.0) "T" 10.0)
        (pool:pvtie (list -50.0 215.0) (list 0.0 215.0) "S" 10.0)
        (pool:pvtie (list -95.0 0.0) (list -95.0 180.0) "A" 10.0)
        (pool:pvtie (list -72.0 125.0) (list -72.0 180.0) "S1" 10.0)
        (pool:pvtie (list -72.0 55.0) (list -72.0 125.0) "V" 10.0)
        (pool:pvtie (list 375.0 -15.0) (list 425.0 40.0) "S2" 10.0))))
  pv)

(defun pool:grecflow (oct / oldclay mode crosses pv imeth pvo ovbad ans xitems
                       nm2 npts grback
                       braw araw traw sraw s1raw vraw s2raw
                       ovres sv tv s1v vov hyp u2 vv2 bact aact sact s1act
                       tp bo le ri ltd lbd lew rtd rbd rew
                       evals edgecons crosscons dac dbd fq q
                       a b c d cen0 ml mr lend rend seed
                       res pts failed notes
                       xmin xmax ymin ymax w hh doff th cen odim
                       e p qq cc nm tgt act rows k fedge fcross)
  (setq oldclay (getvar "CLAYER"))

  ;; perimeter input method first: measure every edge, or the overall
  ;; sheet (A/B overalls with the sides assumed symmetric).  The
  ;; cross-dim detail level is asked later, once the perimeter is in.
  ;; An octagon defaults to Overall -- knowing A and B is enough to
  ;; draw it, since its sides are all the same.
  (setq nm2 (if oct "Octagon" "Grecian")
        npts (if oct pool:*octnpts* pool:*grecnpts*))
  (defun gr:method ()
    (setq imeth (pool:askkw (strcat nm2 " perimeter input")
                            "Measured Overall" "Measured/Overall"
                            (if oct "Overall" nil) nil))
    nil)
  ;; the guide depends on the method, so it is (re)built by the stage
  ;; that follows it -- backing into the method question and out again
  ;; therefore always leaves a guide matching the chosen method
  (defun gr:guide ()
    (pool:pvkill)
    (setq mode "Simple" crosses nil
          pv (pool:grecpreview nil npts)
          pvo (if (= imeth "Overall") (pool:grecovties oct) nil))
    ;; the octagon guide is taller and narrower than the grecian's
    (if oct
        (command "_.ZOOM" "_Window"
                 (pool:wp (list -130.0 -60.0)) (pool:wp (list 360.0 390.0)))
        (command "_.ZOOM" "_Window"
                 (pool:wp (list -130.0 -80.0)) (pool:wp (list 470.0 310.0))))
    nil)
  (princ "\nA gray guide pool is shown -- the RED element is the dimension being asked for.")
  (princ "\nCorners: A/B bottom, C/D top, LT/LB left tips, RT/RB right tips.")

  ;; -------- body + ends: measured edges, or the overall sheet
  (defun gr:perim ( / ans)
   (setq grback nil)
   (if (= imeth "Overall")
      (progn
        (princ (strcat "\nOverall sheet -- symmetric " (strcase nm2 t)
                       "; the RED tie is being asked for."))
        (if oct
            (princ "\nThe cut letters may all be NA: A and B alone draw the octagon."))
        (princ "\n(after the first answer, Back re-asks the previous one)")
        ;; An in-square OCTAGON is square, so its two overalls are one
        ;; measurement, asked once.  A GRECIAN is a long pool -- its A
        ;; and B are never equal -- so it is always asked for both,
        ;; in square or not.
        (setq ans (pool:askseqb
                    (append
                      (if (and oct pool:*insq*)
                          (list (list 'b 'REQ "Overall size (A & B are equal)"
                                      (append (cdr (assoc "B" pvo))
                                              (cdr (assoc "A" pvo)))))
                          (list (list 'b 'REQ "B - overall length" (cdr (assoc "B" pvo)))
                                (list 'a 'REQ "A - overall width" (cdr (assoc "A" pvo)))))
                      (list (list 'tt 'NAX "T - top side length" (cdr (assoc "T" pvo)))
                            (list 'ss 'NAX "S - corner cut along the side" (cdr (assoc "S" pvo)))
                            (list 's1 'NAX "S1 - corner cut down the end" (cdr (assoc "S1" pvo)))
                            (list 'vv 'NAX "V - end width" (cdr (assoc "V" pvo)))
                            (list 's2 'NAX "S2 - corner cut face (check)" (cdr (assoc "S2" pvo)))))
                    t))
        (if (eq ans 'POOL-BACK)
            (setq grback t braw 1.0 araw 1.0 ans nil))
        (setq braw (pool:sq ans 'b)
              araw (if (and oct pool:*insq*) braw (pool:sq ans 'a))
              traw (pool:sq ans 'tt) sraw (pool:sq ans 'ss)
              s1raw (pool:sq ans 's1) vraw (pool:sq ans 'vv)
              s2raw (pool:sq ans 's2)
              ovres (if grback
                        (list 1.0 1.0 1.0 1.0)
                        (if oct
                            (pool:octov araw braw sraw traw s1raw vraw)
                            (pool:grecov araw braw sraw traw s1raw vraw)))
              sv (car ovres) tv (cadr ovres)
              s1v (caddr ovres) vov (cadddr ovres))
        ;; walls beat corners (see pool:grecov): say so when holding a
        ;; taped T / V actually moved the taped S / S1, so the crew can
        ;; see in the report why their corner number came out different
        (if (and traw sraw (> (abs (- sv sraw)) 0.5))
            (princ (strcat "\nT is a wall, so it is held true -- S re-derived "
                           (rtos sraw 2 2) " -> " (rtos sv 2 2) ".")))
        (if (and vraw s1raw (> (abs (- s1v s1raw)) 0.5))
            (princ (strcat "\nV is a wall, so it is held true -- S1 re-derived "
                           (rtos s1raw 2 2) " -> " (rtos s1v 2 2) ".")))
        ;; the sheet letters must close POSITIVE against the overalls;
        ;; a letter that does not fit is adjusted, warned about now,
        ;; and its report rows go red
        (if (<= tv 1.0e-6)
            (progn
              (setq tv (min 12.0 (* 0.25 braw)) sv (/ (- braw tv) 2.0) ovbad t)
              (pool:valnote "OVERALL SHEET FAILED - S + T + S DOES NOT FIT B, ADJUSTED")))
        (if (<= sv 1.0e-6)
            (progn
              (setq sv (min 12.0 (* 0.125 braw)) tv (- braw sv sv) ovbad t)
              (pool:valnote "OVERALL SHEET FAILED - T LONGER THAN B, ADJUSTED")))
        (if (<= vov 1.0e-6)
            (progn
              (setq vov (min 12.0 (* 0.25 araw)) s1v (/ (- araw vov) 2.0) ovbad t)
              (pool:valnote "OVERALL SHEET FAILED - S1 + V + S1 DOES NOT FIT A, ADJUSTED")))
        (if (<= s1v 1.0e-6)
            (progn
              (setq s1v (min 12.0 (* 0.125 araw)) vov (- araw s1v s1v) ovbad t)
              (pool:valnote "OVERALL SHEET FAILED - V LONGER THAN A, ADJUSTED")))
        (setq hyp (sqrt (+ (* sv sv) (* s1v s1v)))
              bo tv tp tv le araw ri araw
              ltd hyp lbd hyp rtd hyp rbd hyp
              lew vov rew vov))
      (progn
        (princ "\n(Back re-asks the previous question)")
        (if pool:*insq*
            (progn
            (setq ans (pool:askseqb
                        (list (list 'bo 'REQ "Side (top & bottom)"
                                    (append (cdr (assoc 'ab pv)) (cdr (assoc 'cd pv))))
                              (list 'le 'REQ "Body end (left & right, A-D / B-C)"
                                    (append (cdr (assoc 'ad pv)) (cdr (assoc 'bc pv))))
                              (list 'ltd 'REQ "LEFT end diagonals (top & bottom)"
                                    (append (cdr (assoc 'ltd pv)) (cdr (assoc 'lbd pv))))
                              (list 'lew 'REQ "LEFT end width (LT-LB)"
                                    (append (cdr (assoc 'lew pv)) (pool:lbl pv '(lLT lLB))))
                              (list 'rtd 'REQ "RIGHT end diagonals (top & bottom)"
                                    (append (cdr (assoc 'rtd pv)) (cdr (assoc 'rbd pv))))
                              (list 'rew 'REQ "RIGHT end width (RT-RB)"
                                    (append (cdr (assoc 'rew pv)) (pool:lbl pv '(lRT lRB)))))
                        t))
            (if (eq ans 'POOL-BACK)
                (setq grback t)
                (setq bo (pool:sq ans 'bo) tp bo
                      le (pool:sq ans 'le) ri le
                      ltd (pool:sq ans 'ltd) lbd ltd
                      lew (pool:sq ans 'lew)
                      rtd (pool:sq ans 'rtd) rbd rtd
                      rew (pool:sq ans 'rew))))
            (progn
            (setq ans (pool:askseqb
                        (list (list 'bo 'REQ "Side BOTTOM (A-B)"
                                    (append (cdr (assoc 'ab pv)) (pool:lbl pv '(lA lB))))
                              (list 'tp 'REQ "Side TOP (D-C)"
                                    (append (cdr (assoc 'cd pv)) (pool:lbl pv '(lD lC))))
                              (list 'le 'REQ "End LEFT (A-D)"
                                    (append (cdr (assoc 'ad pv)) (pool:lbl pv '(lA lD))))
                              (list 'ri 'REQ "End RIGHT (B-C)"
                                    (append (cdr (assoc 'bc pv)) (pool:lbl pv '(lB lC))))
                              (list 'ltd 'REQ "LEFT end diagonal TOP (D-LT)"
                                    (append (cdr (assoc 'ltd pv)) (pool:lbl pv '(lD lLT))))
                              (list 'lbd 'REQ "LEFT end diagonal BOTTOM (A-LB)"
                                    (append (cdr (assoc 'lbd pv)) (pool:lbl pv '(lA lLB))))
                              (list 'lew 'REQ "LEFT end width (LT-LB)"
                                    (append (cdr (assoc 'lew pv)) (pool:lbl pv '(lLT lLB))))
                              (list 'rtd 'REQ "RIGHT end diagonal TOP (C-RT)"
                                    (append (cdr (assoc 'rtd pv)) (pool:lbl pv '(lC lRT))))
                              (list 'rbd 'REQ "RIGHT end diagonal BOTTOM (B-RB)"
                                    (append (cdr (assoc 'rbd pv)) (pool:lbl pv '(lB lRB))))
                              (list 'rew 'REQ "RIGHT end width (RT-RB)"
                                    (append (cdr (assoc 'rew pv)) (pool:lbl pv '(lRT lRB)))))
                        t))
            (if (eq ans 'POOL-BACK)
                (setq grback t)
                (setq bo (pool:sq ans 'bo) tp (pool:sq ans 'tp)
                      le (pool:sq ans 'le) ri (pool:sq ans 'ri)
                      ltd (pool:sq ans 'ltd) lbd (pool:sq ans 'lbd)
                      lew (pool:sq ans 'lew)
                      rtd (pool:sq ans 'rtd) rbd (pool:sq ans 'rbd)
                      rew (pool:sq ans 'rew)))))))
   (if grback 'POOL-BACK nil))

  ;; -------- the perimeter is in: now pick the cross-dim detail level,
  ;; draw those diagonals on the guide, and measure them (NA allowed)
  (defun gr:cross ( / ans xg v)
   (setq crosses nil xg nil)
   (if (not pool:*insq*)
      (progn
        (setq v (pool:askkw (strcat nm2 " cross-dim detail")
                            "Simple Center Complex" "Simple/Center/Complex"
                            nil t))
        (if (eq v 'POOL-BACK) (setq grback t)
            (setq mode v
                  crosses (pool:grecmode mode)
                  xg (mapcar '(lambda (c) (car (cdr (assoc (caddr c) pv))))
                             crosses)
                  pv (pool:greccross crosses pv npts)
                  xg (mapcar '(lambda (c) (car (cdr (assoc (caddr c) pv))))
                             crosses)))))
   (if grback
       'POOL-BACK
       (progn (gr:crossask xg) (if grback 'POOL-BACK nil))))

  (defun gr:crossask (xg / ans)
  (setq crosscons nil xitems nil k 0)
  (foreach e crosses
    (setq xitems (cons (list (read (strcat "x" (itoa k))) 'NAX
                             (strcat "Cross dim " (caddr e))
                             (append (cdr (assoc (caddr e) pv))
                                     (pool:lbl pv
                                       (list (pool:lblkey (nth (car e) pool:*grecnames*))
                                             (pool:lblkey (nth (cadr e) pool:*grecnames*))))))
                       xitems)
          k (1+ k)))
  (setq ans (if xitems (pool:askseqb (reverse xitems) t) nil) k 0)
  (if (eq ans 'POOL-BACK)
      (progn (pool:pvdel xg) (setq grback t crosses nil ans nil)))
  (foreach e crosses
    (setq crosscons (cons (list (car e) (cadr e)
                                (pool:sq ans (read (strcat "x" (itoa k)))))
                          crosscons)
          k (1+ k)))
  (setq crosscons (reverse crosscons))
  (princ))

  ;; ---- the input phase, with Back working right across it
  (pool:stages (list 'gr:method 'gr:guide 'gr:perim 'gr:cross))
  (pool:pvkill)

  ;; -------- seed: fit the body quad, project nominal ends
  (setq evals (list (cons 'ab bo) (cons 'cd tp) (cons 'ad le) (cons 'bc ri)
                    (cons 'rbd rbd) (cons 'rew rew) (cons 'rtd rtd)
                    (cons 'ltd ltd) (cons 'lew lew) (cons 'lbd lbd))
        edgecons (mapcar '(lambda (e)
                            (list (car e) (cadr e) (cdr (assoc (caddr e) evals)) (cadddr e)))
                         pool:*grecedges*)
        dac (pool:crossget crosscons 0 4)
        dbd (pool:crossget crosscons 1 5)
        fq (pool:fitquad bo tp le ri dac dbd pool:*side-tol* pool:*cross-tol*)
        q (car fq)
        a (car q) b (cadr q) c (caddr q) d (cadddr q)
        cen0 (pool:v* (pool:v+ (pool:v+ a b) (pool:v+ c d)) 0.25)
        ml (pool:unit (pool:perp (pool:v- d a))))
  (if (< (pool:dot (pool:v- (pool:mid a d) cen0) ml) 0.0)
      (setq ml (pool:v* ml -1.0)))
  (setq mr (pool:unit (pool:perp (pool:v- c b))))
  (if (< (pool:dot (pool:v- (pool:mid b c) cen0) mr) 0.0)
      (setq mr (pool:v* mr -1.0)))
  (setq lend (pool:grecendp a d ml ltd lbd lew)
        rend (pool:grecendp b c mr rtd rbd rew)
        seed (list a b (cadr rend) (car rend) c d (car lend) (cadr lend))
        notes nil)
  (if (not (nth 5 lend))
      (setq notes (cons "LEFT END: diagonals/width did not fit -- 45 seed used" notes)))
  (if (not (nth 5 rend))
      (setq notes (cons "RIGHT END: diagonals/width did not fit -- 45 seed used" notes)))

  ;; -------- fit: Simple keeps the validated seed; Center/Complex
  ;; best-fit all 8 corners against every provided cross dim.
  ;; The tip-to-tip widths LT-RT and LB-RB are what B WOULD be on an
  ;; ideal grecian, so when measured they are held like WALLS (the
  ;; 1-inch edge band) -- just as the body chords A-D and B-C already
  ;; are -- rather than pulled like cross dims in the 2-inch band.
  ;; They still get their CROSS DIMENSIONS-style dim and report row
  ;; like any tie.
  (if (= mode "Simple")
      (setq pts seed failed (cadr fq))
      (progn
        (setq fedge edgecons fcross nil)
        (foreach cc crosscons
          (if (and (caddr cc) (pool:tippair (car cc) (cadr cc)))
              (setq fedge (append fedge
                                  (list (list (car cc) (cadr cc) (caddr cc)
                                              pool:*side-tol*))))
              (setq fcross (cons cc fcross))))
        (setq res (pool:fitpoly seed fedge (reverse fcross) pool:*cross-tol*)
              pts (car res)
              failed (cadr res))))

  ;; -------- extents / scale
  (setq xmin (apply 'min (mapcar 'car pts))
        xmax (apply 'max (mapcar 'car pts))
        ymin (apply 'min (mapcar 'cadr pts))
        ymax (apply 'max (mapcar 'cadr pts))
        w (- xmax xmin) hh (- ymax ymin)
        doff (max 12.0 (/ (max w hh) 18.0))
        th (max 3.0 (/ (max w hh) 70.0))
        pool:*dashlt* (pool:ltload "DASHED")
        cen (list 0.0 0.0))
  (foreach p pts (setq cen (pool:v+ cen p)))
  (setq cen (pool:v* cen (/ 1.0 8.0)))

  ;; -------- perimeter (POOL) + internal end chords (dashed, POOL-NOTES)
  (foreach e pool:*grecedges*
    (setq p (nth (car e) pts) qq (nth (cadr e) pts))
    (if (member (caddr e) '(ad bc))
        (pool:lined p qq)
        (pool:line p qq "POOL")))

  ;; -------- dimensions (DIMENSION)
  ;; In-square: the field-sheet exterior set only -- S+T share a row
  ;; above the top with B outboard of them, S1+V share a column left
  ;; of the pool with A outboard, and S2 reads once on the
  ;; bottom-right cut.  Every corner is the same corner in square, so
  ;; one of each keeps the sheet clean.  Out-of-square: every edge
  ;; differs, so every edge is dimensioned as before.
  (setvar "CLAYER" "DIMENSION")
  (if pool:*insq*
      (progn
        ;; S: pool's left extreme to the top side start (row 1)
        (setq p (nth 6 pts) qq (nth 5 pts))              ; LT, D
        (pool:dimalg (list (car p) ymax) qq
                     (list (* 0.5 (+ (car p) (car qq))) (+ ymax doff)))
        ;; T: the top side D-C (row 1)
        (pool:dimalg (nth 5 pts) (nth 4 pts)
                     (list (car (pool:mid (nth 5 pts) (nth 4 pts)))
                           (+ ymax doff)))
        ;; B: overall, tip to tip LT-RT (row 2, outboard)
        (pool:dimalg (nth 6 pts) (nth 3 pts)
                     (list (car (pool:mid (nth 6 pts) (nth 3 pts)))
                           (+ ymax (* 1.9 doff))))
        ;; S1: top down to the left tip (column 1)
        (pool:dimalg (list xmin ymax) (nth 6 pts)
                     (list (- xmin doff)
                           (* 0.5 (+ ymax (cadr (nth 6 pts))))))
        ;; V: the left end LT-LB (column 1)
        (pool:dimalg (nth 6 pts) (nth 7 pts)
                     (list (- xmin doff)
                           (cadr (pool:mid (nth 6 pts) (nth 7 pts)))))
        ;; A: overall, the A-D chord (column 2, outboard)
        (pool:dimalg (nth 0 pts) (nth 5 pts)
                     (list (- xmin (* 1.9 doff))
                           (cadr (pool:mid (nth 0 pts) (nth 5 pts)))))
        ;; S2: the bottom-right corner cut, once
        (pool:dimalg (nth 1 pts) (nth 2 pts)
                     (pool:outoffp (nth 1 pts) (nth 2 pts) pts doff)))
      (foreach e pool:*grecedges*
        (setq p (nth (car e) pts) qq (nth (cadr e) pts))
        (cond
          ((= (caddr e) 'ad)            ; left end chord -> outboard left
           (pool:dimalg p qq (list (- xmin (* 0.6 doff)) (cadr (pool:mid p qq)))))
          ((= (caddr e) 'bc)            ; right end chord -> outboard right
           (pool:dimalg p qq (list (+ xmax (* 0.6 doff)) (cadr (pool:mid p qq)))))
          (t
           (pool:dimalg p qq (pool:outoffp p qq pts doff))))))
  ;; provided cross dims, in the CROSS DIMENSIONS style when available
  (setq odim (pool:dimxbegin) k 0)
  (foreach cc crosscons
    (if (caddr cc)
        (pool:dimalg (nth (car cc) pts) (nth (cadr cc) pts)
                     (pool:v+ (pool:mid (nth (car cc) pts) (nth (cadr cc) pts))
                              (pool:v* (pool:unit
                                         (pool:perp (pool:v- (nth (cadr cc) pts)
                                                             (nth (car cc) pts))))
                                       (* (if (= 0 (rem k 2)) 0.12 -0.12) doff)))))
    (setq k (1+ k)))
  (pool:dimxend odim)
  (setvar "CLAYER" oldclay)

  ;; -------- corner labels (kept outside the shape)
  (setq k 0)
  (foreach p pts
    (pool:text (pool:lbloff p cen pts (* 2.0 th)) th (nth k pool:*grecnames*) "POOL-NOTES")
    (setq k (1+ k)))

  ;; -------- report table
  (setq rows nil)
  (foreach e pool:*grecedges*
    (setq nm (pool:grecnm (car e) (cadr e))
          tgt (cdr (assoc (caddr e) evals))
          act (distance (nth (car e) pts) (nth (cadr e) pts))
          rows (cons (list nm tgt act) rows)))
  (foreach cc crosscons
    (setq nm (pool:grecnm (car cc) (cadr cc))
          act (distance (nth (car cc) pts) (nth (cadr cc) pts))
          rows (cons (list (strcat "X " nm) (caddr cc) act) rows)))
  (setq rows (reverse rows))
  ;; overall-sheet letters vs the fitted shape
  (if (= imeth "Overall")
      (progn
        (setq u2 (pool:v- (nth 1 pts) (nth 0 pts))
              vv2 (pool:v- (nth 5 pts) (nth 0 pts))
              bact (distance
                     (pool:linex cen u2 (nth 7 pts) (pool:v- (nth 6 pts) (nth 7 pts)))
                     (pool:linex cen u2 (nth 2 pts) (pool:v- (nth 3 pts) (nth 2 pts))))
              aact (distance
                     (pool:linex cen vv2 (nth 0 pts) u2)
                     (pool:linex cen vv2 (nth 5 pts) (pool:v- (nth 4 pts) (nth 5 pts))))
              sact (abs (pool:dot (pool:v- (nth 6 pts) (nth 5 pts)) (pool:unit u2)))
              s1act (abs (pool:dot (pool:v- (nth 6 pts) (nth 5 pts)) (pool:unit vv2))))
        (setq rows (append rows (list
          (list "OV B" braw bact)
          (list "OV A" araw aact)
          (append (list "OV T" traw (distance (nth 5 pts) (nth 4 pts)))
                  (if ovbad (list t) nil))
          (append (list "OV S" sraw sact) (if ovbad (list t) nil))
          (append (list "OV S1" s1raw s1act) (if ovbad (list t) nil))
          (append (list "OV V" vraw (distance (nth 6 pts) (nth 7 pts)))
                  (if ovbad (list t) nil))
          (list "OV S2" s2raw (distance (nth 5 pts) (nth 6 pts))))))))
  ;; -------- pool bottom (interior pipeline)
  (setq rows (append rows (pool:hopgrecdsp pts doff th)))
  (if failed (setq notes (cons "CROSS DIMS FAILED" notes)))
  (setq notes (append notes pool:*valnotes*))
  (pool:report rows notes (+ xmax (* 2.0 doff)) ymax th "POOL-NOTES")
  (if failed
      (princ "\n*** CROSS DIMS FAILED -- sides held true, see report table ***")
      (princ "\nPool layout complete -- see the report table."))
  (princ))

;;; -------------------- L / Lazy L pools --------------------------------
;;;
;;;  Six-corner pools, one wing:      F -------- E
;;;                                   |           \
;;;    True L: joint D-E is a         |            D ------- C
;;;    square step; Lazy L: D-E       |                      |
;;;    is an angled joint.            A -------------------- B
;;;
;;;  Sides A-B, B-C, C-D, D-E, E-F, F-A plus up to six cross dims
;;;  (A-C, B-D, C-E, D-F, A-E, B-F -- any of them may be NA).

(setq pool:*hexsides* (list '(0 1) '(1 2) '(2 3) '(3 4) '(4 5) '(5 0)))
(setq pool:*hexsidenames* (list "A-B" "B-C" "C-D" "D-E" "E-F" "F-A"))
(setq pool:*hexdiags* (list '(0 2) '(1 3) '(2 4) '(3 5) '(0 4) '(1 5)
                            '(0 3) '(1 4) '(2 5)))
(setq pool:*hexdiagnames* (list "A-C" "B-D" "C-E" "D-F" "A-E" "B-F"
                                "A-D" "B-E" "C-F"))

;; Nominal right-angle (or 45-degree jointed) L built from the given
;; side lengths -- the starting shape for the relaxation fit.
(defun pool:hexguess (sides lazy / ab bc cd de fa a b c d e f)
  (setq ab (nth 0 sides) bc (nth 1 sides) cd (nth 2 sides)
        de (nth 3 sides) fa (nth 5 sides)
        a (list 0.0 0.0)
        b (list ab 0.0))
  (if lazy
      ;; constant-width pool bent 45 degrees (per the reference):
      ;; B-C and D-E are the bend sides, C-D the far end
      (setq c (pool:v+ b (list (* bc 0.7071067812) (* bc 0.7071067812)))
            d (pool:v+ c (list (* cd -0.7071067812) (* cd 0.7071067812)))
            e (pool:v+ d (list (* de -0.7071067812) (* de -0.7071067812)))
            f (list 0.0 fa))
      ;; true L (per the reference): B-C is the full right end, the
      ;; wing sits top-right and the notch top-left
      (setq c (list ab bc)
            d (list (- ab cd) bc)
            e (pool:v- d (list 0.0 de))
            f (pool:v- e (list (nth 4 sides) 0.0))))
  (list a b c d e f))

;; In-square lazy L: hold the direction of every side EXACTLY so the
;; two parallel pairs stay parallel (A-B // E-F and B-C // D-E), rather
;; than letting the relaxation bend the corners to absorb closure
;; error.  The chain A->B->C->D->E is walked at the exact headings
;; (0, 45, 135, 225 degrees) with the measured lengths, then F drops
;; straight down from E onto the left wall (F = (0, Ey)).  Any closure
;; error therefore lands in the LENGTHS of E-F and F-A (visible in the
;; report as small deltas), never in the angles.
(defun pool:hexsquare (sides / u ab bc cd de a b c d e f)
  (setq u 0.7071067812
        ab (nth 0 sides) bc (nth 1 sides)
        cd (nth 2 sides) de (nth 3 sides)
        a (list 0.0 0.0)
        b (list ab 0.0))
  (setq c (pool:v+ b (list (* bc u) (* bc u)))
        d (pool:v+ c (list (* cd (- u)) (* cd u)))
        e (pool:v+ d (list (* de (- u)) (* de (- u))))
        f (list 0.0 (cadr e)))
  (list a b c d e f))

;; Side constraints (banded by +/-band) for the hexagon.
(defun pool:hexsidecon (sides band w / k out pr)
  (setq k 0 out nil)
  (foreach pr pool:*hexsides*
    (setq out (cons (list (car pr) (cadr pr)
                          (- (nth k sides) band) (+ (nth k sides) band) w)
                    out)
          k (1+ k)))
  (reverse out))

;; Exact-pull constraints for the provided (non-NA) cross dims.
(defun pool:hexdiagcon (diags w / k out pr tgt)
  (setq k 0 out nil)
  (foreach pr pool:*hexdiags*
    (setq tgt (nth k diags))
    (if tgt
        (setq out (cons (list (car pr) (cadr pr) tgt tgt w) out)))
    (setq k (1+ k)))
  (reverse out))

;; (max-side-delta max-cross-delta) of a fitted hexagon; NA cross dims
;; are ignored.
(defun pool:hexerr (pts sides diags / k pr smax xmax d)
  (setq smax 0.0 xmax 0.0 k 0)
  (foreach pr pool:*hexsides*
    (setq d (abs (- (distance (nth (car pr) pts) (nth (cadr pr) pts))
                    (nth k sides)))
          smax (max smax d)
          k (1+ k)))
  (setq k 0)
  (foreach pr pool:*hexdiags*
    (if (nth k diags)
        (setq d (abs (- (distance (nth (car pr) pts) (nth (cadr pr) pts))
                        (nth k diags)))
              xmax (max xmax d)))
    (setq k (1+ k)))
  (list smax xmax))

;; Fit the L hexagon (same policy as the quad):
;;  1. sides held true, provided cross dims pulled as close as they
;;     will come; inside tolerance -> done
;;  2. sides may flex inside +/-stol to pull the cross dims in
;;  3. otherwise sides held true, cross dims as close as possible,
;;     failure flag set
;; Returns (pts failed).
(defun pool:fithex (sides diags lazy stol xtol / guess p1 e1 p2 e2 any dg)
  ;; In-square lazy L (no cross dims measured): build the shape at
  ;; exact headings instead of relaxing, so A-B // E-F and B-C // D-E
  ;; hold perfectly and closure error goes to the E-F / F-A lengths.
  (setq any nil)
  (foreach dg diags (if dg (setq any t)))
  (if (and lazy (not any))
      (list (pool:hexsquare sides) nil)
      (pool:fithexr sides diags lazy stol xtol)))

(defun pool:fithexr (sides diags lazy stol xtol / guess p1 e1 p2 e2)
  (setq guess (pool:hexguess sides lazy)
        p1 (pool:relaxn guess
                        (append (pool:hexdiagcon diags 0.4)
                                (pool:hexsidecon sides 0.0 1.0))
                        3000))
  ;; polish: a sides-only pass so the sides land exactly true
  (setq p1 (pool:relaxn p1 (pool:hexsidecon sides 0.0 1.0) 400)
        e1 (pool:hexerr p1 sides diags))
  (if (<= (cadr e1) xtol)
      (list p1 nil)
      (progn
        (setq p2 (pool:relaxn p1
                              (append (pool:hexdiagcon diags 0.5)
                                      (pool:hexsidecon sides stol 1.0))
                              3000)
              e2 (pool:hexerr p2 sides diags))
        (if (and (<= (car e2) (+ stol 0.05)) (<= (cadr e2) (+ xtol 0.05)))
            (list p2 nil)
            (list p1 t)))))

;; Point-in-polygon (ray casting) -- the L is not convex, so side
;; dimensions find "outward" by testing against the actual shape.
(defun pool:inpoly (p poly / n i j xi yi xj yj in x y)
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

;; Midpoint of p->q offset by dist to the side that lies OUTSIDE poly.
(defun pool:outoffp (p q poly dist / m n)
  (setq m (pool:mid p q)
        n (pool:unit (pool:perp (pool:v- q p))))
  (if (pool:inpoly (pool:v+ m (pool:v* n 1.0)) poly)
      (setq n (pool:v* n -1.0)))
  (pool:v+ m (pool:v* n dist)))

;; Corner-label position: away from the centroid, but flipped when
;; that lands inside the shape (the inner corner of an L).
(defun pool:lbloff (p cen poly dist / dir cand)
  (setq dir (pool:unit (pool:v- p cen))
        cand (pool:v+ p (pool:v* dir dist)))
  (if (pool:inpoly cand poly)
      (pool:v+ p (pool:v* dir (- dist)))
      cand))

;; Gray guide for the L shapes: nominal body (solid), the six cross
;; diagonals (DASHED, so outline and cross dims read apart), and
;; corner labels kept clear of the linework.
(defun pool:hexpreview (lazy / pts cen p pr k keys ent all pv lbls)
  (setq pts (if lazy
                (list (list 0.0 0.0) (list 296.0 0.0) (list 414.0 119.0)
                      (list 296.0 238.0) (list 226.0 168.0) (list 0.0 168.0))
                (list (list 0.0 0.0) (list 360.0 0.0) (list 360.0 315.0)
                      (list 225.0 315.0) (list 225.0 180.0) (list 0.0 180.0)))
        cen (list 0.0 0.0))
  (foreach p pts (setq cen (pool:v+ cen p)))
  (setq cen (pool:v* cen (/ 1.0 6.0))
        all nil pv nil)
  (setq keys (list 'ab 'bc 'cd 'de 'ef 'fa) k 0)
  (foreach pr pool:*hexsides*
    (setq ent (pool:pvline (nth (car pr) pts) (nth (cadr pr) pts))
          pv (cons (cons (nth k keys) (list ent)) pv)
          all (cons ent all)
          k (1+ k)))
  ;; the cross diagonals are NOT drawn yet -- pool:hexcross adds them
  ;; once every side length is in (nine diagonals over the shape would
  ;; bury the side being measured)
  (setq lbls (list "A" "B" "C" "D" "E" "F") k 0)
  (foreach p pts
    (pool:text (pool:lbloff p cen pts 20.0) 12.0 (nth k lbls) "POOL-NOTES")
    (setq ent (pool:setcol (entlast) pool:*pv-col*)
          all (cons ent all)
          pv (cons (cons (pool:lblkey (nth k lbls)) (list ent)) pv)
          k (1+ k)))
  (setq pool:*pvents* all)
  pv)

;; Add the nine (eight on a lazy L) cross diagonals to the L guide once
;; the side lengths are in.  Returns the extended highlight assoc.
(defun pool:hexcross (lazy pv / pts keys k ent)
  (setq pts (if lazy
                (list (list 0.0 0.0) (list 296.0 0.0) (list 414.0 119.0)
                      (list 296.0 238.0) (list 226.0 168.0) (list 0.0 168.0))
                (list (list 0.0 0.0) (list 360.0 0.0) (list 360.0 315.0)
                      (list 225.0 315.0) (list 225.0 180.0) (list 0.0 180.0)))
        keys (list 'ac 'bd 'ce 'df 'ae 'bf 'ad 'be 'cf)
        k 0)
  (foreach pr pool:*hexdiags*
    ;; the lazy L omits the B-E joint diagonal (per the reference)
    (if (not (and lazy (equal pr (list 1 4))))
        (setq ent (pool:pvadd (pool:pvlined (nth (car pr) pts)
                                            (nth (cadr pr) pts)))
              pv (cons (cons (nth k keys) (list ent)) pv)))
    (setq k (1+ k)))
  pv)

;; Full guided flow for L / Lazy L pools: preview, prompts, fit, draw,
;; dimension and report.  Caller handles sysvars / undo / zoom-extents.
(defun pool:hexflow (lazy / oldclay pv sides diags res pts failed notes ans hxr
                            cen p pr k w hh xmin xmax ymax ymin doff th
                            odim rows lbls dv mquad sq4 elast
                            octy ocsz icty icsz oc ic hcs hce hcarcs)
  (setq oldclay (getvar "CLAYER"))
  (setq pv (pool:hexpreview lazy))
  (command "_.ZOOM" "_Window"
           (pool:wp (list -80.0 -70.0)) (pool:wp (list 520.0 370.0)))
  (princ "\nA gray guide pool is shown -- the RED element is the dimension being asked for.")
  (princ "\nCorners: A bottom-left, B bottom-right, C right end top, D inner corner, E wing corner, F top-left.")
  (princ "\n(Back re-asks the previous question, right back to the start)")
  (defun hx:sides ( / ans)
  (setq ans (pool:askseqb
              (mapcar '(lambda (q)
                         (list (car q) 'REQ (cadr q)
                               (append (cdr (assoc (caddr q) pv))
                                       (pool:lbl pv (cadddr q)))))
                      (if lazy
                          (list (list 'ab "Main side A-B (bottom)" 'ab '(lA lB))
                                (list 'bc "Lower bend side B-C (45 deg)" 'bc '(lB lC))
                                (list 'cd "Far end C-D" 'cd '(lC lD))
                                (list 'de "Upper bend side D-E (45 deg)" 'de '(lD lE))
                                (list 'ef "Top side E-F" 'ef '(lE lF))
                                (list 'fa "Left end F-A" 'fa '(lF lA)))
                          (list (list 'ab "Side A-B (bottom, full length)" 'ab '(lA lB))
                                (list 'bc "End B-C (right end, full height)" 'bc '(lB lC))
                                (list 'cd "Side C-D (top of wing)" 'cd '(lC lD))
                                (list 'de "Step D-E (down to the inner corner)" 'de '(lD lE))
                                (list 'ef "Side E-F (top of main section)" 'ef '(lE lF))
                                (list 'fa "End F-A (left end)" 'fa '(lF lA)))))
              nil)
        sides (mapcar '(lambda (k) (pool:sq ans k)) '(ab bc cd de ef fa)))
    nil)
  ;; cross dims only when out-of-square; in-square squares up to sides.
  ;; The diagonals join the guide now that the sides are all in.
  (defun hx:diags ( / ans)
  (if (not pool:*insq*) (setq pv (pool:hexcross lazy pv)))
  (setq diags
        (if pool:*insq*
            (list nil nil nil nil nil nil nil nil nil)
            (progn
              (setq ans (pool:askseqb
                          (mapcar '(lambda (q)
                                     (list (car q) 'NAX
                                           (strcat "Cross dim " (cadr q))
                                           (append (cdr (assoc (car q) pv))
                                                   (pool:lbl pv (caddr q)))))
                                  (append
                                    (list (list 'ac "A-C" '(lA lC))
                                          (list 'bd "B-D" '(lB lD))
                                          (list 'ce "C-E" '(lC lE))
                                          (list 'df "D-F" '(lD lF))
                                          (list 'ae "A-E" '(lA lE))
                                          (list 'bf "B-F" '(lB lF))
                                          (list 'ad "A-D" '(lA lD)))
                                    ;; the lazy L's bend joint is not taped
                                    (if lazy nil (list (list 'be "B-E" '(lB lE))))
                                    (list (list 'cf "C-F" '(lC lF)))))
                          t))
              (if (eq ans 'POOL-BACK)
                  'POOL-BACK
                  (list (pool:sq ans 'ac) (pool:sq ans 'bd) (pool:sq ans 'ce)
                        (pool:sq ans 'df) (pool:sq ans 'ae) (pool:sq ans 'bf)
                        (pool:sq ans 'ad) (if lazy nil (pool:sq ans 'be))
                        (pool:sq ans 'cf))))))
  (if (eq diags 'POOL-BACK) 'POOL-BACK nil))

  ;; corner treatments, like the rectangle: the five OUTER corners
  ;; take one answer; the INNER corner (E) is typically different, so
  ;; it is asked separately (Enter reuses the outer answer).
  ;;
  ;; The body is FIT first, at the top of this stage rather than after
  ;; the questions, because a treatment's setback depends on the real
  ;; corner angle and on an L those are never all 90 degrees -- a lazy
  ;; L bends 135 at B and E even in-square, and out-of-square every
  ;; corner drifts.  Fitting here (not as its own stage) keeps Back
  ;; working: an extra always-succeeding stage would swallow the Back
  ;; out of the corner question by falling straight forward again.
  ;; Re-entering after a Back re-fits, which is what changing a side
  ;; or a diagonal should do.
  (defun hx:corners ( / v k oang mins de ef icap)
    (princ "\nFitting pool body to the measurements ...")
    (setq res (pool:fithex sides diags lazy pool:*side-tol* pool:*cross-tol*)
          pts (car res)
          failed (cadr res)
          octy "Square" ocsz 0.0 icty "Square" icsz 0.0)
    (setq v (pool:askyn "Are the corners modified (rounded / chamfered)"
                        "No" t))
    (cond
      ((eq v 'POOL-BACK) 'POOL-BACK)
      ((not v) nil)
      (t
       ;; one answer covers the five OUTER corners (0 1 2 3 5), so it
       ;; has to hold for the SHARPEST of them -- that is the one whose
       ;; cut reaches furthest along its walls.  Budget: half the
       ;; shortest fitted wall, which with the sharpest angle on both
       ;; ends of every wall can never overrun any of them.
       (setq oang (pool:polywedge pts 0) mins nil)
       (foreach k '(1 2 3 5)
         (setq oang (min oang (pool:polywedge pts k))))
       (foreach k pool:*hexsides*
         (setq de (distance (nth (car k) pts) (nth (cadr k) pts))
               mins (if mins (min mins de) de)))
       (setq oc (pool:askcorner "OUTER corners" nil nil nil
                                (* 0.5 mins) oang t))
       (if (eq oc 'POOL-BACK)
           'POOL-BACK
           (progn
             (setq octy (car oc) ocsz (cadr oc))
             ;; E is capped by what the outer cuts actually LEFT on its
             ;; two walls, at each of those corners' own angles
             (setq de (- (distance (nth 3 pts) (nth 4 pts))
                         (* ocsz (pool:cornerk octy (pool:polywedge pts 3))))
                   ef (- (distance (nth 4 pts) (nth 5 pts))
                         (* ocsz (pool:cornerk octy (pool:polywedge pts 5))))
                   icap (max 0.0 (min de ef))
                   ic (pool:askcorner "INNER corner (E)" octy ocsz nil
                                      icap (pool:polywedge pts 4) t))
             (if (eq ic 'POOL-BACK)
                 'POOL-BACK
                 (progn (setq icty (car ic) icsz (cadr ic)) nil)))))))

  (pool:stages (list 'hx:sides 'hx:diags 'hx:corners))
  (pool:pvkill)

  ;; pts / res / failed were fit at the top of hx:corners, so the
  ;; corner questions could be sized against the real corner angles
  (setq notes nil
        xmin (apply 'min (mapcar 'car pts))
        xmax (apply 'max (mapcar 'car pts))
        ymin (apply 'min (mapcar 'cadr pts))
        ymax (apply 'max (mapcar 'cadr pts))
        w (- xmax xmin)
        hh (- ymax ymin)
        doff (max 12.0 (/ (max w hh) 18.0))
        th (max 3.0 (/ (max w hh) 70.0))
        pool:*dashlt* (pool:ltload "DASHED")
        cen (list 0.0 0.0))
  (foreach p pts (setq cen (pool:v+ cen p)))
  (setq cen (pool:v* cen (/ 1.0 6.0)))

  ;; perimeter (layer POOL) -- mark the drawing so the whole pool can
  ;; be mirrored later if the user asks.  Corner treatments cut in
  ;; exactly like the rectangle's: sides run between the treatment
  ;; ends, an arc or chamfer face closes each corner (square corners
  ;; degenerate to the plain corner-to-corner sides).  E (index 4) is
  ;; the inner corner and carries its own treatment; the wedge math in
  ;; pool:cornerends handles the reflex angle as-is.
  (setq elast (entlast))
  (setq hcs (list (list octy ocsz) (list octy ocsz) (list octy ocsz)
                  (list octy ocsz) (list icty icsz) (list octy ocsz))
        hce (mapcar '(lambda (k)
                       (pool:cornerends (nth k pts)
                                        (nth (rem (+ k 5) 6) pts)
                                        (nth (rem (+ k 1) 6) pts)
                                        (car (nth k hcs)) (cadr (nth k hcs))
                                        nil))
                    (list 0 1 2 3 4 5)))
  (foreach pr pool:*hexsides*            ; side i: eNext(i) -> ePrev(i+1)
    (pool:line (cadr (nth (car pr) hce)) (car (nth (cadr pr) hce)) "POOL"))
  (setq hcarcs nil k 0)
  (foreach p hcs
    (cond
      ((= (car p) "Diag")
       (pool:line (car (nth k hce)) (cadr (nth k hce)) "POOL")
       (setq hcarcs (cons nil hcarcs)))
      ((= (car p) "Rounded")
       (pool:arc3p (car (nth k hce)) (caddr (nth k hce)) (cadr (nth k hce))
                   "POOL")
       (setq hcarcs (cons (entlast) hcarcs)))
      (t (setq hcarcs (cons nil hcarcs))))
    (setq k (1+ k)))
  (setq hcarcs (reverse hcarcs))

  ;; dimensions (layer DIMENSION) -- side dims read to the TRUE
  ;; corners, same convention as the rectangle
  (setvar "CLAYER" "DIMENSION")
  (foreach pr pool:*hexsides*
    (pool:dimalg (nth (car pr) pts) (nth (cadr pr) pts)
                 (pool:outoffp (nth (car pr) pts) (nth (cadr pr) pts)
                               pts doff)))
  ;; corner annotations: one Typ. callout on an outer corner (B), the
  ;; inner corner E dimensioned on its own
  (if (/= octy "Square")
      (pool:dimcorner1 (nth 1 hce) octy (nth 1 hcarcs)
                       (pool:unit (pool:v- (nth 1 pts) cen)) doff " Typ."))
  (if (/= icty "Square")
      (pool:dimcorner1 (nth 4 hce) icty (nth 4 hcarcs)
                       (pool:unit
                         (pool:v+ (pool:unit (pool:v- (nth 3 pts) (nth 4 pts)))
                                  (pool:unit (pool:v- (nth 5 pts) (nth 4 pts)))))
                       doff ""))
  ;; provided cross dims, in the CROSS DIMENSIONS style when available
  (setq odim (pool:dimxbegin) k 0)
  (foreach pr pool:*hexdiags*
    (if (nth k diags)
        (pool:dimalg (nth (car pr) pts) (nth (cadr pr) pts)
                     (pool:v+ (pool:mid (nth (car pr) pts) (nth (cadr pr) pts))
                              (pool:v* (pool:unit
                                         (pool:perp
                                           (pool:v- (nth (cadr pr) pts)
                                                    (nth (car pr) pts))))
                                       (* (if (= 0 (rem k 2)) 0.15 -0.15)
                                          doff)))))
    (setq k (1+ k)))
  (pool:dimxend odim)
  (setvar "CLAYER" oldclay)

  ;; corner labels (kept outside the shape -- D is a reflex corner)
  (setq lbls (list "A" "B" "C" "D" "E" "F") k 0)
  (foreach p pts
    (pool:text (pool:lbloff p cen pts (* 2.0 th)) th (nth k lbls) "POOL-NOTES")
    (setq k (1+ k)))

  ;; report table
  (setq rows nil k 0)
  (foreach pr pool:*hexsides*
    (setq rows (cons (list (strcat "SIDE " (nth k pool:*hexsidenames*))
                           (nth k sides)
                           (distance (nth (car pr) pts) (nth (cadr pr) pts)))
                     rows)
          k (1+ k)))
  (if (not pool:*insq*)
      (progn
        (setq k 0)
        (foreach pr pool:*hexdiags*
          (setq rows (cons (list (strcat "CROSS " (nth k pool:*hexdiagnames*))
                                 (nth k diags)
                                 (distance (nth (car pr) pts) (nth (cadr pr) pts)))
                           rows)
                k (1+ k)))))
  (setq rows (reverse rows))
  (if (/= octy "Square")
      (setq rows (append rows (list
        (list (if (= octy "Rounded") "OUTER CORNER RAD" "OUTER CORNER FACE")
              ocsz ocsz)))))
  (if (/= icty "Square")
      (setq rows (append rows (list
        (list (if (= icty "Rounded") "INNER CORNER RAD" "INNER CORNER FACE")
              icsz icsz)))))

  ;; -------- standard hopper in the main section (no sport for L).
  ;; dv = the virtual main-section corner where the break line (down
  ;; from inner corner E) meets the main-run line A-B; the hopper
  ;; anchors off the main rectangle A-dv-E-F and its left corners tie
  ;; to A and F.  A and F are REAL pool corners, so when the outer
  ;; corner treatment cuts them, the ties must land on the ends of
  ;; that cut -- exactly like the rectangle's hopper -- not on the
  ;; sharp corner behind it.  dv and E are not real treated walls in
  ;; this virtual frame (dv has no corner at all; E's real treatment
  ;; is sized for the true reflex angle against D, not against dv), so
  ;; they stay plain "Square" the way they always have.
  (if (pool:askyn "Add pool bottom (hopper) detail?" "Yes" nil)
      (progn
        ;; per the reference: the break line drops from the inner
        ;; corner E to the bottom side, and the hopper lives in the
        ;; main section A - breakBottom - E - F
        (setq dv (pool:linex (nth 4 pts) (pool:v- (nth 5 pts) (nth 0 pts))
                             (nth 0 pts) (pool:v- (nth 1 pts) (nth 0 pts)))
              mquad (list (nth 0 pts) dv (nth 4 pts) (nth 5 pts))
              sq4 (list (list octy ocsz) (list "Square" 0.0)
                        (list "Square" 0.0) (list octy ocsz)))
        (command "_.ZOOM" "_Window"
                 (pool:wp (list (- (apply 'min (mapcar 'car mquad)) doff)
                                (- (apply 'min (mapcar 'cadr mquad)) doff)))
                 (pool:wp (list (+ (apply 'max (mapcar 'car mquad)) doff)
                                (+ (apply 'max (mapcar 'cadr mquad)) doff))))
        ;; L pools take the standard hopper only
        (setq rows (append rows
                           (pool:hopnormal mquad sq4 doff th t "Normal"
                                           (apply 'min (mapcar 'car pts))
                                           (- (apply 'min (mapcar 'cadr pts))
                                              (* 2.2 doff))
                                           t)))))

  ;; -------- all dimensions are in: offer to mirror the pool.
  ;; Top-to-bottom, so the wing swaps sides but the deep end (and its
  ;; hopper) stays on the left -- see pool:mirrory.
  (if (pool:askyn "Mirror the pool (flips the wing; deep end stays left)"
                  "No" nil)
      (progn
        (pool:mirrory elast (cadr (pool:wp (list 0.0 (* 0.5 (+ ymin ymax))))))
        (princ "\nPool mirrored -- the wing swapped sides, deep end still on the left.")))

  (if failed (setq notes (cons "CROSS DIMS FAILED" notes)))
  (setq notes (append notes pool:*valnotes*))
  (pool:report rows notes (+ xmax (* 2.0 doff)) ymax th "POOL-NOTES")
  (if failed
      (princ "\n*** CROSS DIMS FAILED -- sides held true, see report table ***")
      (princ "\nPool layout complete -- see the report table."))
  (princ))

;;; -------------------- report table -----------------------------------

;; Report cell: red when the row is flagged.
(defun pool:rtext (pt h str lay red)
  (if red (pool:textc pt h str lay 1) (pool:text pt h str lay)))

;; rows  = list of (label target actual [red])
;; notes = list of failure strings (written big and red)
(defun pool:report (rows notes x y h lay / lh ytop y0 xr r tgt act dl ds n)
  (setq lh (* 2.2 h)
        ytop (+ y lh)
        xr (+ x (* 46.0 h))
        y ytop)
  (setq y (- y lh))
  (pool:text (list x y) (* 1.25 h) "POOL LAYOUT REPORT" lay)
  (setq y (- y lh))
  (pool:text (list x y) h "MEASUREMENT" lay)
  (pool:text (list (+ x (* 20.0 h)) y) h "TARGET" lay)
  (pool:text (list (+ x (* 29.0 h)) y) h "ACTUAL" lay)
  (pool:text (list (+ x (* 38.0 h)) y) h "DELTA" lay)
  ;; a 4th row element flags the row RED: the validator adjusted it
  (foreach r rows
    (setq y (- y lh)
          tgt (cadr r)
          act (caddr r))
    (pool:rtext (list x y) h (car r) lay (nth 3 r))
    (if tgt
        (progn
          (setq dl (- act tgt)
                ds (strcat (if (< dl 0.0) "" "+") (rtos dl 2 2)))
          (pool:rtext (list (+ x (* 20.0 h)) y) h (rtos tgt 2 2) lay (nth 3 r))
          (pool:rtext (list (+ x (* 38.0 h)) y) h ds lay (nth 3 r)))
        ;; NA target: measurement was not taken in the field
        (progn
          (pool:rtext (list (+ x (* 20.0 h)) y) h "N/A" lay (nth 3 r))
          (pool:rtext (list (+ x (* 38.0 h)) y) h "-" lay (nth 3 r))))
    (pool:rtext (list (+ x (* 29.0 h)) y) h (rtos act 2 2) lay (nth 3 r)))
  (foreach n notes
    (setq y (- y (* 1.5 lh)))
    (pool:textc (list x y) (* 1.4 h) n lay 1))
  (setq y0 (- y lh)
        ytop (+ ytop (* 0.6 lh)))
  (pool:line (list (- x h) y0) (list xr y0) lay)
  (pool:line (list xr y0) (list xr ytop) lay)
  (pool:line (list xr ytop) (list (- x h) ytop) lay)
  (pool:line (list (- x h) ytop) (list (- x h) y0) lay)
  (princ))


;;; -------------------- rectangle corner treatments --------------------
;;;
;;;  A rectangle corner may be Square, Rounded (radius) or Diag
;;;  (chamfer).  Side lengths are always measured to the TRUE (sharp)
;;;  corner; the treatment cuts inward from there.  The size typed is:
;;;    Rounded -> the corner RADIUS
;;;    Diag    -> the CHAMFER FACE length (the cut itself)
;;;  In-square pools assume all four corners identical; out-of-square
;;;  pools ask per corner (Enter reuses the previous corner's answer).

;; The two points where a corner's treatment meets the straight sides
;; (toward the previous / next corner) plus, for Rounded, the arc mid.
;; Returns (ePrev eNext arcMid|nil).  Square -> (P P nil).
;; ctype "Ends" is the escape hatch for corners that are not a plain
;; treatment of this quad's corner (a Grecian's angled cut, say): size
;; and xtra ARE the two treatment ends, prev-side first.
;; The wedge angle the two walls at p actually make (0..pi), measured
;; from p toward its previous and next corners.  A reflex corner is
;; measured by the wedge its walls make, not the 360-minus angle --
;; which is what the treatment geometry wants either way.
(defun pool:wedge (p pp pn / u v dp)
  (setq u (pool:unit (pool:v- pp p))
        v (pool:unit (pool:v- pn p))
        dp (pool:dot u v))
  (atan (sqrt (max 0.0 (- 1.0 (* dp dp)))) dp))

;; Same, for corner i of a closed polygon.
(defun pool:polywedge (pts i / n)
  (setq n (length pts))
  (pool:wedge (nth i pts)
              (nth (rem (+ i (1- n)) n) pts)
              (nth (rem (+ i 1) n) pts)))

;; How far a corner treatment eats along EACH adjacent wall, per unit
;; of entered size, at wedge angle ang:
;;   Rounded  radius r -> r / tan(ang/2)
;;   Diag     face   f -> f / (2 sin(ang/2))
;; At 90 degrees these come to 1.0 and 0.70711, which is what the old
;; fixed arithmetic assumed -- but they diverge fast away from square
;; (a 60-degree Rounded corner sets back 1.73 x its radius, a
;; 135-degree one only 0.41 x), so anything sizing a treatment against
;; the wall it has to fit on must ask for the real angle.  L and Lazy
;; L pools are the ones that care: their bends are 135 degrees even
;; in-square, and out-of-square every corner drifts off 90.
(defun pool:cornerk (ctype ang / h s)
  (setq h (* 0.5 ang) s (sin h))
  (if (< s 1.0e-9)
      1.0e9                             ; degenerate: treat as unusable
      (cond ((= ctype "Rounded") (/ (cos h) s))
            ((= ctype "Diag") (/ 1.0 (* 2.0 s)))
            (t 0.0))))

(defun pool:cornerends (p pp pn ctype size xtra / uprev unext ang sb bis cen)
  (setq uprev (pool:unit (pool:v- pp p))
        unext (pool:unit (pool:v- pn p))
        ang (pool:wedge p pp pn))                          ; interior angle
  (cond
    ((= ctype "Ends") (list size xtra nil))
    ((= ctype "Diag")
     (setq sb (/ size (* 2.0 (sin (/ ang 2.0)))))           ; face -> edge setback
     (list (pool:v+ p (pool:v* uprev sb))
           (pool:v+ p (pool:v* unext sb)) nil))
    ((= ctype "Rounded")
     (setq sb (/ (* size (cos (/ ang 2.0))) (sin (/ ang 2.0)))  ; r/tan(ang/2)
           bis (pool:unit (pool:v+ uprev unext))
           cen (pool:v+ p (pool:v* bis (/ size (sin (/ ang 2.0))))))
     (list (pool:v+ p (pool:v* uprev sb))
           (pool:v+ p (pool:v* unext sb))
           (pool:v- cen (pool:v* bis size))))              ; arc point nearest corner
    (t (list p p nil))))

;; A reference point at corner i of quad q for a cross-dim measurement:
;;   spec = 'true (sharp corner) | 'prev | 'next (treatment ends) |
;;          'mid (chamfer/arc middle).
(defun pool:cornerpoint (q corners i spec / ce)
  (setq ce (pool:cornerends (nth i q)
                            (nth (rem (+ i 3) 4) q)
                            (nth (rem (+ i 1) 4) q)
                            (car (nth i corners)) (cadr (nth i corners))
                            (caddr (nth i corners))))
  (cond ((eq spec 'prev) (car ce))
        ((eq spec 'next) (cadr ce))
        ((eq spec 'mid) (if (caddr ce) (caddr ce) (pool:mid (car ce) (cadr ce))))
        (t (nth i q))))

;; Draw the rectangle perimeter with corner treatments on layer POOL.
;; Returns the list of fillet-arc entity names per corner (nil where
;; the corner is square or chamfered) for the corner dimensions.
(defun pool:drawrect (q corners / ce i tyi arcs)
  (setq ce (mapcar '(lambda (i)
                      (pool:cornerends (nth i q)
                                       (nth (rem (+ i 3) 4) q)
                                       (nth (rem (+ i 1) 4) q)
                                       (car (nth i corners)) (cadr (nth i corners))
                                       (caddr (nth i corners))))
                   (list 0 1 2 3)))
  (foreach i (list 0 1 2 3)             ; straight sides (eNext(i) -> ePrev(i+1))
    (pool:line (cadr (nth i ce)) (car (nth (rem (+ i 1) 4) ce)) "POOL"))
  (setq arcs nil)
  (foreach i (list 0 1 2 3)             ; corner treatments
    (setq tyi (car (nth i corners)))
    (cond
      ((= tyi "Diag")
       (pool:line (car (nth i ce)) (cadr (nth i ce)) "POOL")
       (setq arcs (cons nil arcs)))
      ((= tyi "Rounded")
       (pool:arc3p (car (nth i ce)) (caddr (nth i ce)) (cadr (nth i ce)) "POOL")
       (setq arcs (cons (entlast) arcs)))
      (t (setq arcs (cons nil arcs)))))
  (reverse arcs))

;; Corner annotations for the rectangle.  In-square pools get a single
;; "Typ." note at the bottom-right corner (B): the radius or chamfer
;; measurement with a Typ. suffix, or a 90-degree leader for square
;; corners.  Out-of-square pools dim every corner individually --
;; radius dim, chamfer dim, or the ACTUAL angular dimension for a
;; square corner.  Assumes CLAYER is already DIMENSION.
;; One corner-treatment annotation: a radius dim on a fillet arc or an
;; aligned dim on a chamfer face, dropped outward along outd, with an
;; optional " Typ." suffix.  Square corners are not this helper's job.
(defun pool:dimcorner1 (ce ty arc outd doff sfx / am fm od)
  (cond
    ((= ty "Rounded")
     (setq am (caddr ce)
           od (pool:dimsbegin (if (and arc (entget arc))
                                  (cdr (assoc 40 (entget arc)))
                                  (distance (car ce) (cadr ce)))))
     (if (= sfx "")
         (command "_.DIMRADIUS" (list arc (pool:wp am))
                  (pool:wp (pool:v+ am (pool:v* outd (* 0.9 doff)))))
         (command "_.DIMRADIUS" (list arc (pool:wp am))
                  "_T" (strcat "<>" sfx)
                  (pool:wp (pool:v+ am (pool:v* outd (* 0.9 doff))))))
     (pool:dimsend od))
    ((= ty "Diag")
     (setq fm (pool:mid (car ce) (cadr ce))
           od (pool:dimsbegin (distance (car ce) (cadr ce))))
     (if (= sfx "")
         (command "_.DIMALIGNED" (pool:wp (car ce)) (pool:wp (cadr ce))
                  (pool:wp (pool:v+ fm (pool:v* outd (* 0.5 doff)))))
         (command "_.DIMALIGNED" (pool:wp (car ce)) (pool:wp (cadr ce))
                  "_T" (strcat "<>" sfx)
                  (pool:wp (pool:v+ fm (pool:v* outd (* 0.5 doff))))))
     (pool:dimsend od))))

(defun pool:dimcorners (quad corners arcs cen doff / ilist sfx i cc ce p pp pn
                                                    ty outd fm p1 p2)
  (if pool:*insq*
      (setq ilist (list 1) sfx " Typ.")
      (setq ilist (list 0 1 2 3) sfx ""))
  (foreach i ilist
    (setq p (nth i quad)
          pp (nth (rem (+ i 3) 4) quad)
          pn (nth (rem (+ i 1) 4) quad)
          cc (nth i corners)
          ty (car cc)
          ce (pool:cornerends p pp pn ty (cadr cc) (caddr cc))
          outd (pool:unit (pool:v- p cen)))
    (cond
      ((or (= ty "Rounded") (= ty "Diag"))
       (pool:dimcorner1 ce ty (nth i arcs) outd doff sfx))
      (t                                ; Square
       (if (= sfx "")
           (progn                       ; the actual corner angle
             (setq p1 (pool:v+ p (pool:v* (pool:unit (pool:v- pp p)) (* 0.8 doff)))
                   p2 (pool:v+ p (pool:v* (pool:unit (pool:v- pn p)) (* 0.8 doff)))
                   fm (pool:v+ p (pool:v* (pool:unit (pool:v- cen p)) doff)))
             (command "_.DIMANGULAR" ""
                      (pool:wp p) (pool:wp p1) (pool:wp p2) (pool:wp fm)))
           (command "_.LEADER" (pool:wp p)
                    (pool:wp (pool:v+ p (pool:v* outd (* 1.2 doff))))
                    "" "90%%d Typ." ""))))))

;; Re-draw the guide rectangle's corners with the chosen treatments so
;; the visual matches what will be built.  gq = the guide quad,
;; corners = per-corner (type size), sizes already clamped for display.
;; The four full-length guide sides are replaced by shortened sides
;; plus gray chamfer lines / fillet arcs; the pv assoc side keys are
;; re-pointed at the new side entities.  Returns the updated pv.
(defun pool:pvcorners (pv gq corners / ce i k cc ent)
  (foreach k (list 'ab 'bc 'dc 'da)
    (pool:pvdel (cdr (assoc k pv))))
  (setq ce (mapcar '(lambda (i)
                      (pool:cornerends (nth i gq)
                                       (nth (rem (+ i 3) 4) gq)
                                       (nth (rem (+ i 1) 4) gq)
                                       (car (nth i corners)) (cadr (nth i corners))
                                       (caddr (nth i corners))))
                   (list 0 1 2 3)))
  ;; shortened straight sides (side i runs corner i -> corner i+1)
  (setq i 0)
  (foreach k (list 'ab 'bc 'dc 'da)
    (setq ent (pool:pvadd (pool:pvline (cadr (nth i ce))
                                       (car (nth (rem (+ i 1) 4) ce))))
          pv (subst (cons k (list ent)) (assoc k pv) pv)
          i (1+ i)))
  ;; the corner treatments themselves
  (setq i 0)
  (foreach cc corners
    (cond
      ((= (car cc) "Diag")
       (pool:pvadd (pool:pvline (car (nth i ce)) (cadr (nth i ce)))))
      ((= (car cc) "Rounded")
       (pool:arc3p (car (nth i ce)) (caddr (nth i ce)) (cadr (nth i ce))
                   "POOL-NOTES")
       (pool:pvadd (pool:setcol (entlast) pool:*pv-col*))))
    (setq i (1+ i)))
  pv)

;; Prompt one corner's treatment (Enter reuses prevty/prevsz).
;; maxsb caps the treatment's setback along the walls at half the
;; shorter adjacent wall, so two treatments can never overlap and fold
;; the perimeter; too-large answers are re-asked.
;; ang = the wedge angle to size this answer against (the SHARPEST of
;; them when one answer covers several corners, since that is the one
;; that eats furthest into its walls).  nil means "assume square",
;; which is right for the rectangle: it asks its corners before the
;; cross dims, so its true angles are not known yet -- and a pool
;; still called a rectangle is within a degree of 90 anyway.
(defun pool:askcorner (label prevty prevsz ents maxsb ang back
                       / ty sz cols sb wed)
  (setq cols (mapcar 'pool:getcol ents))
  (foreach e ents (pool:setcol e pool:*hi-col*))
  (pool:osup)
  (setq ty (pool:askkw label "Square Rounded Diag" "Square/Rounded/Diag"
                       prevty back))
  (pool:osdown)
  (if (eq ty 'POOL-BACK)
      (progn (mapcar '(lambda (e c) (pool:setcol e c)) ents cols)
             (setq ty nil)))
  (if (null ty)
      (progn (mapcar '(lambda (e c) (pool:setcol e c)) ents cols)
             (setq sz nil)))
  (if (null ty)
      nil
  (if (= ty "Square")
      (setq sz 0.0)
      (progn
        (pool:osup)
        (initget (if (and prevsz (> prevsz 0.0)) 6 7))
        (setq sz (getdist (strcat "\n" label
                                  (if (= ty "Rounded") " corner radius" " chamfer face length")
                                  (if (and prevsz (> prevsz 0.0))
                                      (strcat " <" (rtos prevsz) ">") "")
                                  ": ")))
        (if (null sz) (setq sz prevsz))
        ;; how far this treatment eats along each wall, at the real
        ;; corner angle -- so the cap holds on a 135-degree bend or a
        ;; skewed out-of-square corner, not just on a square one
        (setq wed (if ang ang (/ pi 2.0)))
        (while (and maxsb
                    (> (setq sb (* sz (pool:cornerk ty wed))) maxsb))
          (princ (strcat "\nToo large for this corner's walls -- max "
                         (rtos (/ maxsb (pool:cornerk ty wed)))
                         ".  Re-enter."))
          (initget 7)
          (setq sz (getdist (strcat "\n" label
                                    (if (= ty "Rounded") " corner radius"
                                        " chamfer face length")
                                    ": "))))
        (pool:osdown))))
  (mapcar '(lambda (e c) (pool:setcol e c)) ents cols)
  (if ty (list ty sz) 'POOL-BACK))

;; Cross-dim measurement templates for the chosen reference mode.
;; Each entry: (diagkey prompt rowlabel iA specA iC specC).  Ends uses
;; both endpoints on each side of the diagonal.
(defun pool:crosstemplate (cmode)
  (cond
    ((= cmode "Middle")
     (list (list 'ac "Cross dim A-C (to corner middles)" "AC MID" 0 'mid 2 'mid)
           (list 'bd "Cross dim B-D (to corner middles)" "BD MID" 1 'mid 3 'mid)))
    ;; The two ties of a diagonal CROSS each other, the way the tape
    ;; actually runs: each starts at one end of a corner treatment and
    ;; finishes at the OPPOSITE end of the far treatment.  Pairing the
    ;; same side at both corners would give two near-parallel ties,
    ;; which pin the out-of-squareness down far less.
    ((= cmode "Ends")
     (list (list 'ac "Cross A-C (A>B end to C>D end)" "AC B-D" 0 'next 2 'next)
           (list 'ac "Cross A-C (A>D end to C>B end)" "AC D-B" 0 'prev 2 'prev)
           (list 'bd "Cross B-D (B>A end to D>C end)" "BD A-C" 1 'prev 3 'prev)
           (list 'bd "Cross B-D (B>C end to D>A end)" "BD C-A" 1 'next 3 'next)))
    (t
     (list (list 'ac "Cross dim bottom-left to top-right (A-C)" "CROSS A-C" 0 'true 2 'true)
           (list 'bd "Cross dim bottom-right to top-left (B-D)" "CROSS B-D" 1 'true 3 'true)))))

;; Average of a diagonal's raw measurements (bootstrap), or the
;; corner-corrected effective true-corner target using estimate q.
(defun pool:rawavg (xmeas diagkey / sum n)
  (setq sum 0.0 n 0)
  (foreach m xmeas
    (if (and (eq (car m) diagkey) (nth 7 m))
        (setq sum (+ sum (nth 7 m)) n (1+ n))))
  (if (> n 0) (/ sum n) nil))

(defun pool:effcross (q corners xmeas diagkey / sum n ra rc)
  (setq sum 0.0 n 0)
  (foreach m xmeas
    (if (and (eq (car m) diagkey) (nth 7 m))
        (progn
          (setq ra (pool:cornerpoint q corners (nth 3 m) (nth 4 m))
                rc (pool:cornerpoint q corners (nth 5 m) (nth 6 m))
                sum (+ sum (+ (nth 7 m)
                              (- (distance (nth (nth 3 m) q) (nth (nth 5 m) q))
                                 (distance ra rc))))
                n (1+ n)))))
  (if (> n 0) (/ sum n) nil))

;;; -------------------- pool bottom / hopper (rectangle) ---------------
;;;
;;;  Field-sheet letters (plan view):
;;;
;;;      D ------------------------------------ C
;;;      |\        M                           /|
;;;      | htl --------- htr                 /  |
;;;      |  |   hopper    |  \            brkt  |
;;;      |H |G    (G x L) |     \           |   |
;;;      | hbl --------- hbr       \        | E |
;;;      |/        K          \       \   brkb  |
;;;      A ------------------------------------ B
;;;
;;;  H = left end -> hopper, G = hopper length, F = hopper -> slope
;;;  break (CHECK), E = slope break -> right end, M = top -> hopper,
;;;  L = hopper width (CHECK), K = hopper -> bottom.  The primary dims
;;;  are perimeter OFFSETS (H, E, M, K) plus the hopper size G; F and
;;;  L are redundant and reported as checks with their deltas.
;;;  The hopper's left corners tie to the pool's left corners -- to the
;;;  end-wall end of the corner treatment when that corner is cut or
;;;  rounded -- and its right corners tie to the slope-break ends.

;; Intersection of two infinite lines (p1 along d1, p2 along d2).
(defun pool:linex (p1 d1 p2 d2 / den s)
  (setq den (- (* (car d1) (cadr d2)) (* (cadr d1) (car d2))))
  (if (> (abs den) 1.0e-9)
      (progn
        (setq s (/ (- (* (- (car p2) (car p1)) (cadr d2))
                      (* (- (cadr p2) (cadr p1)) (car d2)))
                   den))
        (pool:v+ p1 (pool:v* d1 s)))
      ;; parallel lines never truly happen on sane input; a degenerate
      ;; fit must not crash a caller with nil, so fall back to the
      ;; midpoint of the two anchor points
      (pool:mid p1 p2)))

;; The side p->q offset inward (toward cen) by dist, as (point dir).
(defun pool:offline (p q cen dist / n)
  (setq n (pool:unit (pool:perp (pool:v- q p))))
  (if (> (pool:dot (pool:v- (pool:mid p q) cen) n) 0.0)
      (setq n (pool:v* n -1.0)))
  (list (pool:v+ p (pool:v* n dist)) (pool:v- q p)))

;; All hopper geometry for quad + corner treatments + the primary
;; offsets.  Returns an assoc list of named points: hopper corners
;; (hbl htl hbr htr), slope-break ends (brkb brkt), left tie anchors
;; (lab lat), and the measuring-chain points -- horizontal pl phl phr
;; pbrk pr, vertical pb phb pht pt (through the hopper centre).
(defun pool:hopcalc (quad corners h g e m k / a b c d cen hl hr ht hb brk
                                              hbl htl hbr htr brkb brkt
                                              lab1 lab2 lat1 lat2
                                              rab1 rab2 rat1 rat2
                                              hc hdir vdir hc2)
  (setq a (car quad) b (cadr quad) c (caddr quad) d (cadddr quad)
        cen (pool:v* (pool:v+ (pool:v+ a b) (pool:v+ c d)) 0.25)
        hl (pool:offline a d cen h)
        hr (pool:offline a d cen (+ h g))
        ht (pool:offline d c cen m)
        hb (pool:offline a b cen k)
        brk (pool:offline b c cen e)
        hbl (pool:linex (car hl) (cadr hl) (car hb) (cadr hb))
        htl (pool:linex (car hl) (cadr hl) (car ht) (cadr ht))
        hbr (pool:linex (car hr) (cadr hr) (car hb) (cadr hb))
        htr (pool:linex (car hr) (cadr hr) (car ht) (cadr ht))
        brkb (pool:linex (car brk) (cadr brk) a (pool:v- b a))
        brkt (pool:linex (car brk) (cadr brk) d (pool:v- c d))
        ;; both ends of each left corner treatment (Square -> both ends
        ;; coincide with the true corner)
        lab1 (pool:cornerpoint quad corners 0 'prev)
        lab2 (pool:cornerpoint quad corners 0 'next)
        lat1 (pool:cornerpoint quad corners 3 'next)
        lat2 (pool:cornerpoint quad corners 3 'prev)
        ;; and the same for the right corners, used when E = 0 puts the
        ;; slope break on the end wall: the floor breaks to the ends of
        ;; the corner treatment, not to the sharp corner behind it
        rab1 (pool:cornerpoint quad corners 1 'prev)
        rab2 (pool:cornerpoint quad corners 1 'next)
        rat1 (pool:cornerpoint quad corners 2 'next)
        rat2 (pool:cornerpoint quad corners 2 'prev)
        hc (pool:v* (pool:v+ (pool:v+ hbl htl) (pool:v+ hbr htr)) 0.25)
        hdir (pool:v- b a)
        vdir (pool:v- d a)
        ;; H/G/F/E chain sits below the hopper centre by 12" or L/6
        ;; (2/3 down from the top of L), whichever is closer; the
        ;; M/L/K chain sits 12" right of the hopper's right edge
        hc2 (pool:v- hc (pool:v* (pool:unit vdir)
                                 (min 12.0 (/ (distance hbr htr) 6.0)))))
  (list (list 'hbl hbl) (list 'htl htl) (list 'hbr hbr) (list 'htr htr)
        (list 'brkb brkb) (list 'brkt brkt)
        (list 'lab1 lab1) (list 'lab2 lab2)
        (list 'lat1 lat1) (list 'lat2 lat2)
        (list 'rab1 rab1) (list 'rab2 rab2)
        (list 'rat1 rat1) (list 'rat2 rat2)
        (list 'pl (pool:linex hc2 hdir a (pool:v- d a)))
        (list 'phl (pool:linex hc2 hdir (car hl) (cadr hl)))
        (list 'phr (pool:linex hc2 hdir (car hr) (cadr hr)))
        (list 'pbrk (pool:linex hc2 hdir (car brk) (cadr brk)))
        (list 'pr (pool:linex hc2 hdir b (pool:v- c b)))
        ;; M/L/K attach to the hopper's right edge itself; the dim
        ;; line floats 12" further right via 'voff
        (list 'pb (pool:linex (car hr) (cadr hr) a (pool:v- b a)))
        (list 'phb hbr)
        (list 'pht htr)
        (list 'pt (pool:linex (car hr) (cadr hr) d (pool:v- c d)))
        (list 'voff (pool:v* (pool:unit hdir) pool:*mlkoff*))
        ;; G = 0 collapses the pad to a single deep line; E = 0 puts the
        ;; slope break on the end wall, which is already drawn
        (list 'zg (< g 1.0e-6))
        (list 'ze (< e 1.0e-6))))

;; Draw the hopper, slope break and corner ties on layer lay.  Each
;; hopper left corner ties to BOTH ends of its pool corner treatment
;; (one line when the corner is square and the ends coincide).
;; tie = draw the left corner ties (off for shapes whose "left end" is
;; an arc rather than a pair of corners).
(defun pool:hopdraw (gg lay tie / hbl htl hbr htr brkb brkt lab1 lab2 lat1 lat2
                                  rab1 rab2 rat1 rat2)
  (setq hbl (cadr (assoc 'hbl gg)) htl (cadr (assoc 'htl gg))
        hbr (cadr (assoc 'hbr gg)) htr (cadr (assoc 'htr gg))
        brkb (cadr (assoc 'brkb gg)) brkt (cadr (assoc 'brkt gg))
        lab1 (cadr (assoc 'lab1 gg)) lab2 (cadr (assoc 'lab2 gg))
        lat1 (cadr (assoc 'lat1 gg)) lat2 (cadr (assoc 'lat2 gg))
        rab1 (cadr (assoc 'rab1 gg)) rab2 (cadr (assoc 'rab2 gg))
        rat1 (cadr (assoc 'rat1 gg)) rat2 (cadr (assoc 'rat2 gg)))
  (pool:line hbl htl lay)               ; deep-end line (the whole pad when G=0)
  (if (not (cadr (assoc 'zg gg)))
      (progn
        (pool:line htl htr lay)
        (pool:line htr hbr lay)
        (pool:line hbr hbl lay)))
  (if tie
      (progn
        (pool:line lab1 hbl lay)
        (if (> (distance lab1 lab2) 1.0e-6) (pool:line lab2 hbl lay))
        (pool:line lat1 htl lay)
        (if (> (distance lat1 lat2) 1.0e-6) (pool:line lat2 htl lay))))
  (if (and (cadr (assoc 'ze gg)) tie)
      ;; E = 0: the break IS the end wall, so the floor breaks to BOTH
      ;; ends of each right corner treatment -- the same rule the left
      ;; corners follow -- rather than to the sharp corner behind it
      (progn
        (pool:line rab1 hbr lay)
        (if (> (distance rab1 rab2) 1.0e-6) (pool:line rab2 hbr lay))
        (pool:line rat1 htr lay)
        (if (> (distance rat1 rat2) 1.0e-6) (pool:line rat2 htr lay)))
      (progn
        (if (not (cadr (assoc 'ze gg))) (pool:line brkb brkt lay))
        (pool:line htr brkt lay)
        (pool:line hbr brkb lay))))

;;; -------------------- bottom styles ----------------------------------
;;;
;;;  Every one of these is the standard hopper's plan language -- the
;;;  same H/G/F/E/M/L/K chain, deep-end line, slope break and corner
;;;  ties -- with G and/or E pinned to zero, plus the side profile the
;;;  style implies (per the reference drawing):
;;;
;;;    Normal     full hopper, plan only.  A G of 0 turns it into a
;;;               Slope bottom and the profile appears automatically.
;;;    Wedge      G=0, E=0: a deep line at H, floor rising all the way
;;;               to the far wall.
;;;    SLope      G=0: a deep line at H, floor rising to a full-width
;;;               break, then flat to the far wall.
;;;    MOdflat    E=0: one flat pad inset H / G / F, sloping up to the
;;;               walls all round, no shallow flat.
;;;    SHallow    full hopper whose shallow floor is not flat -- it
;;;               slopes from C2 at the break up to C at the wall.

;; Per style: (ask-G ask-E has-profile ask-C2 slack-index).  The slack
;; member absorbs any mismatch when the whole chain was given: G where
;; there is a pad, F where the deep end is a line.
(defun pool:btmspec (style)
  (cond
    ((= style "Wedge")   (list nil nil t   nil 2))
    ((= style "SLope")   (list nil t   t   nil 2))
    ((= style "MOdflat") (list t   nil t   nil 1))
    ((= style "SHallow") (list t   t   t   t   1))
    (t                   (list t   t   nil nil 1))))

;; Nominal guide proportions (h g e) for the style's preview.
(defun pool:btmnom (style len)
  (cond
    ((= style "Wedge")   (list (* 0.12 len) 0.0 0.0))
    ((= style "SLope")   (list (* 0.12 len) 0.0 (* 0.30 len)))
    ((= style "MOdflat") (list (* 0.10 len) (* 0.70 len) 0.0))
    (t                   (list (* 0.12 len) (* 0.20 len) (* 0.40 len)))))

;; Bottom vertices ((run . depth) ...) between the two wall bottoms,
;; left (deep end) to right.  wh = wall height, dp = deep depth,
;; c2 = depth where the shallow floor meets the slope break.
(defun pool:btmbrks (style h g f wh dp c2)
  (cond
    ((= style "Wedge")   (list (cons h dp)))
    ((= style "MOdflat") (list (cons h dp) (cons (+ h g) dp)))
    ((= style "SHallow") (list (cons h dp) (cons (+ h g) dp)
                               (cons (+ h g f) c2)))
    ;; SLope, and a Normal hopper whose G came out at 0
    (t                   (list (cons h dp) (cons (+ h g f) wh)))))

;; Letters the style prompts for, in order, with their chain points.
(defun pool:btmties (style / sp)
  (setq sp (pool:btmspec style))
  (append (list (list "H" 'pl 'phl))
          (if (car sp) (list (list "G" 'phl 'phr)) nil)
          (list (list "F" 'phr 'pbrk))
          (if (cadr sp) (list (list "E" 'pbrk 'pr)) nil)
          (list (list "M" 'pht 'pt) (list "L" 'phb 'pht)
                (list "K" 'pb 'phb))))

;; Gray field-sheet guide inside the fitted pool: nominal hopper,
;; break line and ties (solid), plus a dashed lettered measuring tie
;; per input.  Returns the highlight assoc keyed by letter.
(defun pool:hopguide (quad corners th style tie / len wid nom gg pr tl e et pv)
  (setq len (distance (car quad) (cadr quad))
        wid (distance (car quad) (cadddr quad))
        nom (pool:btmnom style len)
        gg (pool:hopcalc quad corners
                         (car nom) (cadr nom) (caddr nom)
                         (* 0.25 wid) (* 0.25 wid)))
  (foreach pr (append (list (list 'hbl 'htl))
                      (if (cadr (assoc 'zg gg)) nil
                          (list (list 'htl 'htr) (list 'htr 'hbr)
                                (list 'hbr 'hbl)))
                      (if (cadr (assoc 'ze gg)) nil (list (list 'brkb 'brkt)))
                      (if tie
                          (list (list 'lab1 'hbl) (list 'lab2 'hbl)
                                (list 'lat1 'htl) (list 'lat2 'htl))
                          nil)
                      ;; E = 0 breaks to the right corner treatments
                      (if (and (cadr (assoc 'ze gg)) tie)
                          (list (list 'rab1 'hbr) (list 'rab2 'hbr)
                                (list 'rat1 'htr) (list 'rat2 'htr))
                          (list (list 'htr 'brkt) (list 'hbr 'brkb))))
    (pool:pvadd (pool:pvline (cadr (assoc (car pr) gg))
                             (cadr (assoc (cadr pr) gg)))))
  (setq pv nil)
  (foreach tl (pool:btmties style)
    (setq e (pool:pvadd (pool:pvlined (cadr (assoc (cadr tl) gg))
                                      (cadr (assoc (caddr tl) gg)))))
    (pool:text (pool:v+ (pool:mid (cadr (assoc (cadr tl) gg))
                                  (cadr (assoc (caddr tl) gg)))
                        (list (* 0.5 th) (* 0.5 th)))
               (* 1.2 th) (car tl) "POOL-NOTES")
    (setq et (pool:pvadd (pool:setcol (entlast) pool:*pv-col*))
          pv (cons (cons (car tl) (list e et)) pv)))
  pv)

;; Resolve a bottom measurement chain against the pool total:
;;   * NA (nil) entries take the remainder -- split evenly when there
;;     is more than one
;;   * when every value is provided but the sum misses the total, the
;;     slack member at index islack (G on the horizontal chain, L on
;;     the vertical) absorbs the difference; islack -1 = nobody (the
;;     caller handles the residual itself)
;; Returns the resolved list.
(defun pool:chainfix (vals total islack / sum n share out k v)
  (setq sum 0.0 n 0)
  (foreach v vals (if v (setq sum (+ sum v)) (setq n (1+ n))))
  (setq out nil k 0)
  (if (> n 0)
      (progn
        (setq share (/ (- total sum) n))
        (foreach v vals (setq out (cons (if v v share) out))))
      (foreach v vals
        (setq out (cons (if (and (= k islack)
                                 (> (abs (- sum total)) 1.0e-6))
                            (+ v (- total sum))
                            v)
                        out)
              k (1+ k))))
  (reverse out))

;; Post-check a resolved chain: no member may be negative.  A member
;; that resolved below zero is lifted to a positive floor (12", or a
;; share of the total on a small pool) and the deficit comes out of
;; the LARGEST other member -- e.g. a G that went negative is drawn
;; 1' long and F gives up the difference.  Returns (vals fixed):
;; fixed holds the index of every member changed (the lifted one AND
;; its donor) so the caller can flag their dims and report rows red.
(defun pool:chainval (vals total / out fixed n i j v flo need big bigi w)
  (setq n (length vals)
        flo (min 12.0 (/ (abs total) (* 4.0 n)))
        out vals fixed nil i 0)
  (while (< i n)
    (setq v (nth i out))
    (if (< v -1.0e-6)
        (progn
          (setq need (- flo v) big -1.0e30 bigi nil j 0)
          (foreach w out
            (if (and (/= j i) (> w big)) (setq big w bigi j))
            (setq j (1+ j)))
          (setq out (pool:setnth (pool:setnth out i flo) bigi (- big need))
                fixed (append fixed (list i bigi)))))
    (setq i (1+ i)))
  (list out fixed))

;; Record a validation problem: an immediate command-line warning now,
;; and a red note under the report table later.
(defun pool:valnote (msg)
  (setq pool:*valnotes* (append pool:*valnotes* (list msg)))
  (princ (strcat "\n*** " msg " ***"))
  (princ))

;; The adjusted letters as "G/F" for a note.
(defun pool:fixnames (fixed labels / out i)
  (setq out "")
  (foreach i fixed
    (setq out (strcat out (if (= out "") "" "/") (nth i labels))))
  out)

;; Color the just-drawn dimension red (a measurement the validator had
;; to adjust).
(defun pool:dimred ( / e ed)
  (setq e (entlast))
  (if (and e (setq ed (entget e)))
      (entmod (if (assoc 62 ed)
                  (subst (cons 62 1) (assoc 62 ed) ed)
                  (append ed (list (cons 62 1)))))))

;; Report row, red-flagged when index i is among the adjusted ones.
(defun pool:vrow (label tgt act i fixed)
  (append (list label tgt act) (if (member i fixed) (list t) nil)))

;; Deep depth must beat the wall height; C2 must land between them.
(defun pool:askdeep (msg ents wh / dp)
  (setq dp (pool:askh msg ents))
  (while (<= dp wh)
    (princ (strcat "\nD must be deeper than the wall height C ("
                   (rtos wh) ") -- re-enter."))
    (setq dp (pool:askh msg ents)))
  dp)

(defun pool:askc2 (msg ents wh dp / c2)
  (setq c2 (pool:askh msg ents))
  (while (or (< c2 wh) (> c2 dp))
    (princ (strcat "\nC2 must be between C (" (rtos wh) ") and D ("
                   (rtos dp) ") -- re-enter."))
    (setq c2 (pool:askh msg ents)))
  c2)

;; Hopper-language bottom: lettered guide, the H/G/F/E/M/L/K chain,
;; plan hopper + chain dims, and -- for every style but Normal -- the
;; side profile below with its depth dims.
;; style = Normal / Wedge / SLope / MOdflat / SHallow (see above);
;; x0/y0 place the side profile below the pool; tie draws the left
;; corner ties.
(defun pool:hopnormal (quad corners doff th lmode style x0 y0 tie
                       / pv h g f e m l k gg tl odl sp whn hdn nom
                         hraw graw fraw eraw mraw lraw kraw wh dp c2
                         a b c d cen toth totv hres vres skipe rows
                         cv hfx vfx ans lmode2 toth2)
  (setq sp (pool:btmspec style))
  ;; wall-to-wall totals through the pool centre: B1 along the run,
  ;; V1 across it
  (setq a (car quad) b (cadr quad) c (caddr quad) d (cadddr quad)
        cen (pool:v* (pool:v+ (pool:v+ a b) (pool:v+ c d)) 0.25)
        toth (distance (pool:linex cen (pool:v- b a) a (pool:v- d a))
                       (pool:linex cen (pool:v- b a) b (pool:v- c b)))
        totv (distance (pool:linex cen (pool:v- d a) a (pool:v- b a))
                       (pool:linex cen (pool:v- d a) d (pool:v- c d))))
  (setq pv (pool:hopguide quad corners th style tie))
  ;; the profile styles get a nominal section under the plan, so the
  ;; depth prompts highlight a tie the same way the plan letters do
  (if (caddr sp)
      (progn
        (setq whn (* 0.25 totv) hdn (* 0.55 totv)
              nom (pool:btmnom style toth))
        (pool:profdraw x0 y0 toth whn
                       (pool:btmbrks style (car nom) (cadr nom)
                                     (- toth (car nom) (cadr nom) (caddr nom))
                                     whn hdn (* 0.5 (+ whn hdn)))
                       "POOL-NOTES" t)
        (setq pv (append pv
                   (list (pool:pvtie (list (+ x0 toth (* 0.6 doff)) y0)
                                     (list (+ x0 toth (* 0.6 doff)) (- y0 whn))
                                     "C" th)
                         (pool:pvtie (list (+ x0 (car nom)) y0)
                                     (list (+ x0 (car nom)) (- y0 hdn))
                                     "D" th))
                   (if (cadddr sp)
                       (list (pool:pvtie
                               (list (- (+ x0 toth) (caddr nom)) y0)
                               (list (- (+ x0 toth) (caddr nom))
                                     (- y0 (* 0.5 (+ whn hdn))))
                               "C2" th))
                       nil)))))
  (princ "\nPool bottom -- offsets from the perimeter; the RED tie is the one being asked for.")
  (princ "\n(after the first answer, Back re-asks the previous one)")
  ;; L pools: when H+G+F are all given and already span the main
  ;; section (B1), the break lands on the inner corner and E is moot.
  ;; H, M and K are usually the same offset, so M/K suggest the last
  ;; one entered -- Enter accepts it.
  (setq lmode2 lmode toth2 toth
        ans (pool:askseq
              (append
                (list (list 'h 'NAX "H - left end to deep end" (cdr (assoc "H" pv))))
                (if (car sp)
                    (list (list 'g 'ZER (if (= style "MOdflat")
                                            "G - flat pad length"
                                            "G - hopper length, 0 = slope bottom")
                                (cdr (assoc "G" pv))))
                    (list (list 'g 'NAX "G" nil nil ''t)))
                (list (list 'f 'NAX (if (= style "MOdflat")
                                        "F - pad to right end"
                                        "F - deep end to slope break")
                            (cdr (assoc "F" pv)))
                      (list 'e 'NAX "E - slope break to right end"
                            (cdr (assoc "E" pv)) nil
                            '(or (not (cadr sp))
                                 (and lmode2 (pool:sq ans 'h) (pool:sq ans 'g)
                                      (pool:sq ans 'f)
                                      (<= (abs (- (+ (pool:sq ans 'h) (pool:sq ans 'g)
                                                     (pool:sq ans 'f))
                                                  toth2))
                                          0.5)))
                            "\nH + G + F span the main section -- E not needed.")
                      (list 'm 'SUG "M - top side to deep end" (cdr (assoc "M" pv)) '(h))
                      (list 'l 'NAX "L - deep end width" (cdr (assoc "L" pv)))
                      (list 'k 'SUG "K - deep end to bottom side"
                            (cdr (assoc "K" pv)) '(m h)))))
        hraw (pool:sq ans 'h) graw (pool:sq ans 'g) fraw (pool:sq ans 'f)
        eraw (pool:sq ans 'e) mraw (pool:sq ans 'm) lraw (pool:sq ans 'l)
        kraw (pool:sq ans 'k)
        skipe (and (cadr sp) (equal eraw 0.0)))
  (if (not (car sp)) (setq graw 0.0))
  (if (not (cadr sp)) (setq eraw 0.0))
  ;; depths, while the nominal section is still on screen
  (if (caddr sp)
      (setq wh (pool:askh "C - wall height (shallow depth)" (cdr (assoc "C" pv)))
            dp (pool:askdeep "D - deep end depth" (cdr (assoc "D" pv)) wh)
            c2 (if (cadddr sp)
                   (pool:askc2 "C2 - depth where the shallow floor meets the break"
                               (cdr (assoc "C2" pv)) wh dp)
                   wh)))
  (pool:pvkill)
  ;; resolve the chains: NA takes the remainder (split when several);
  ;; the style's slack member (G with a pad, F without) absorbs any
  ;; leftover, and L does across the pool
  (setq hres (pool:chainfix (list hraw graw fraw eraw) toth (nth 4 sp))
        vres (pool:chainfix (list mraw lraw kraw) totv 1)
        cv (pool:chainval hres toth) hres (car cv) hfx (cadr cv)
        cv (pool:chainval vres totv) vres (car cv) vfx (cadr cv)
        h (car hres) g (cadr hres) f (caddr hres) e (cadddr hres)
        m (car vres) l (cadr vres) k (caddr vres))
  ;; a chain member that resolved negative was floored and its donor
  ;; trimmed: both get RED dims and RED report rows below
  (if hfx (pool:valnote (strcat "BOTTOM LENGTHS FAILED - "
                                (pool:fixnames hfx '("H" "G" "F" "E"))
                                " ADJUSTED, VERIFY")))
  (if vfx (pool:valnote (strcat "BOTTOM WIDTHS FAILED - "
                                (pool:fixnames vfx '("M" "L" "K"))
                                " ADJUSTED, VERIFY")))
  ;; a G that came out at zero is a slope bottom whatever was asked
  ;; for, so the section comes along automatically
  (if (< g 1.0e-6) (setq g 0.0))
  (if (and (= g 0.0) (not (caddr sp)))
      (progn
        (princ "\nG = 0 -- that is a slope bottom, so a side view is drawn too.")
        (setq wh (pool:askh "C - wall height (shallow depth)" nil)
              dp (pool:askdeep "D - deep end depth" nil wh)
              c2 wh)))
  (setq gg (pool:hopcalc quad corners h g e m k))
  (pool:hopdraw gg "POOL" tie)
  ;; side profile below the plan, per the style
  (if wh
      (pool:profdraw x0 y0 toth wh
                     (pool:btmbrks (if (caddr sp) style "SLope")
                                   h g f wh dp c2)
                     "POOL" nil))
  ;; chain dimensions along the two centerlines, like the sheet
  (setq odl (getvar "CLAYER"))
  (setvar "CLAYER" "DIMENSION")
  ;; M/L/K def points sit on the hopper edge; their dim line floats
  ;; 30" right via the 'voff vector
  (foreach tl (list (list 'pl 'phl nil (member 0 hfx))
                    (list 'phl 'phr nil (member 1 hfx))
                    (list 'phr 'pbrk nil (member 2 hfx))
                    (list 'pbrk 'pr nil (member 3 hfx))
                    (list 'pht 'pt t (member 0 vfx))
                    (list 'phb 'pht t (member 1 vfx))
                    (list 'pb 'phb t (member 2 vfx)))
    ;; a pinned-out letter (G with no pad, E on the wall) has nothing
    ;; to dimension
    (if (> (distance (cadr (assoc (car tl) gg)) (cadr (assoc (cadr tl) gg)))
           1.0e-6)
        (progn
          (pool:dimalg (cadr (assoc (car tl) gg)) (cadr (assoc (cadr tl) gg))
                       (pool:v+ (pool:mid (cadr (assoc (car tl) gg))
                                          (cadr (assoc (cadr tl) gg)))
                                (if (caddr tl) (cadr (assoc 'voff gg))
                                    (list 0.0 0.0))))
          (if (cadddr tl) (pool:dimred)))))
  ;; profile depths: C at the shallow wall, D at the deep end.  These
  ;; belong to the section, so they join pool:*profents* and stay put
  ;; when an L pool's plan is mirrored.
  (if wh
      (progn
        (pool:dimalg (list (+ x0 toth) y0) (list (+ x0 toth) (- y0 wh))
                     (list (+ x0 toth (* 0.8 doff)) (- y0 (* 0.5 wh))))
        (setq pool:*profents* (cons (entlast) pool:*profents*))
        (pool:dimalg (list (+ x0 h) y0) (list (+ x0 h) (- y0 dp))
                     (list (+ x0 h (* -0.5 doff)) (- y0 (* 0.5 dp))))
        (setq pool:*profents* (cons (entlast) pool:*profents*))
        (if (cadddr sp)
            (progn
              (pool:dimalg (list (+ x0 h g f) y0) (list (+ x0 h g f) (- y0 c2))
                           (list (+ x0 h g f (* 0.3 doff)) (- y0 (* 0.5 c2))))
              (setq pool:*profents* (cons (entlast) pool:*profents*))))))
  (setvar "CLAYER" odl)
  (setq rows (list
    (pool:vrow "HOP H" hraw (distance (cadr (assoc 'pl gg)) (cadr (assoc 'phl gg))) 0 hfx)
    (pool:vrow "HOP G" (if (car sp) graw nil)
               (distance (cadr (assoc 'phl gg)) (cadr (assoc 'phr gg))) 1 hfx)
    (pool:vrow "HOP F" fraw (distance (cadr (assoc 'phr gg)) (cadr (assoc 'pbrk gg))) 2 hfx)
    (pool:vrow "HOP E" (if (or skipe (not (cadr sp))) nil eraw)
               (distance (cadr (assoc 'pbrk gg)) (cadr (assoc 'pr gg))) 3 hfx)
    (pool:vrow "HOP M" mraw (distance (cadr (assoc 'pht gg)) (cadr (assoc 'pt gg))) 0 vfx)
    (pool:vrow "HOP L" lraw (distance (cadr (assoc 'phb gg)) (cadr (assoc 'pht gg))) 1 vfx)
    (pool:vrow "HOP K" kraw (distance (cadr (assoc 'pb gg)) (cadr (assoc 'phb gg))) 2 vfx)))
  (if wh
      (setq rows (append rows
                         (list (list "WALL HT C" wh wh)
                               (list "DEPTH D" dp dp))
                         (if (cadddr sp)
                             (list (list "BRK DEPTH C2" c2 c2))
                             nil))))
  rows)


;; Offset an infinite line (pt dir) toward cen by dist -> (pt dir).
(defun pool:offln (ln cen dist / n)
  (setq n (pool:unit (pool:perp (cadr ln))))
  (if (> (pool:dot (pool:v- (car ln) cen) n) 0.0)
      (setq n (pool:v* n -1.0)))
  (list (pool:v+ (car ln) (pool:v* n dist)) (cadr ln)))

;; Sport bottom PLAN geometry (per the reference drawing): full-width
;; break lines at the outer breaks, the deep flat drawn as a rectangle
;; inset M/K from the side walls, and corner diagonals tying the outer
;; breaks to the deep-flat corners -- the standard hopper language.
;; Chain points follow the standard-hopper placement rules.
(defun pool:hopsportc (lline rline bline tline cen e2 f2 g f1 e1 m k
                       / obl dfl dfr obr dfb dft oblb oblt obrb obrt
                         dbl dtl dbr dtr hc hc2 up)
  (setq obl (pool:offln lline cen e2)
        dfl (pool:offln lline cen (+ e2 f2))
        dfr (pool:offln lline cen (+ e2 f2 g))
        obr (pool:offln lline cen (+ e2 f2 g f1))
        dfb (pool:offln bline cen k)
        dft (pool:offln tline cen m)
        oblb (pool:linex (car obl) (cadr obl) (car bline) (cadr bline))
        oblt (pool:linex (car obl) (cadr obl) (car tline) (cadr tline))
        obrb (pool:linex (car obr) (cadr obr) (car bline) (cadr bline))
        obrt (pool:linex (car obr) (cadr obr) (car tline) (cadr tline))
        dbl (pool:linex (car dfl) (cadr dfl) (car dfb) (cadr dfb))
        dtl (pool:linex (car dfl) (cadr dfl) (car dft) (cadr dft))
        dbr (pool:linex (car dfr) (cadr dfr) (car dfb) (cadr dfb))
        dtr (pool:linex (car dfr) (cadr dfr) (car dft) (cadr dft))
        hc (pool:v* (pool:v+ (pool:v+ dbl dtl) (pool:v+ dbr dtr)) 0.25)
        up (pool:unit (cadr lline))
        hc2 (pool:v- hc (pool:v* up (min 12.0 (/ (distance dbr dtr) 6.0)))))
  (list (list 'oblb oblb) (list 'oblt oblt)
        (list 'obrb obrb) (list 'obrt obrt)
        (list 'dbl dbl) (list 'dtl dtl) (list 'dbr dbr) (list 'dtr dtr)
        (list 'pl (pool:linex hc2 (cadr bline) (car lline) (cadr lline)))
        (list 'pobl (pool:linex hc2 (cadr bline) (car obl) (cadr obl)))
        (list 'pdfl (pool:linex hc2 (cadr bline) (car dfl) (cadr dfl)))
        (list 'pdfr (pool:linex hc2 (cadr bline) (car dfr) (cadr dfr)))
        (list 'pobr (pool:linex hc2 (cadr bline) (car obr) (cadr obr)))
        (list 'pr (pool:linex hc2 (cadr bline) (car rline) (cadr rline)))
        ;; M/L/K attach to the deep flat's right edge; dim line +12"
        (list 'pb (pool:linex (car dfr) (cadr dfr) (car bline) (cadr bline)))
        (list 'pdb dbr)
        (list 'pdt dtr)
        (list 'pt (pool:linex (car dfr) (cadr dfr) (car tline) (cadr tline)))
        (list 'voff (pool:v* (pool:unit (cadr bline)) pool:*mlkoff*))))

(defun pool:hopsportdraw (gg nopad lay pvflag / oblb oblt obrb obrt
                                                dbl dtl dbr dtr)
  (setq oblb (cadr (assoc 'oblb gg)) oblt (cadr (assoc 'oblt gg))
        obrb (cadr (assoc 'obrb gg)) obrt (cadr (assoc 'obrt gg))
        dbl (cadr (assoc 'dbl gg)) dtl (cadr (assoc 'dtl gg))
        dbr (cadr (assoc 'dbr gg)) dtr (cadr (assoc 'dtr gg)))
  (pool:hgl oblb oblt lay pvflag)
  (pool:hgl obrb obrt lay pvflag)
  (if nopad
      (pool:hgl dbl dtl lay pvflag)     ; G = 0: the V line
      (progn
        (pool:hgl dbl dtl lay pvflag)
        (pool:hgl dtl dtr lay pvflag)
        (pool:hgl dtr dbr lay pvflag)
        (pool:hgl dbr dbl lay pvflag)))
  (pool:hgl oblb dbl lay pvflag)
  (pool:hgl oblt dtl lay pvflag)
  (pool:hgl obrb dbr lay pvflag)
  (pool:hgl obrt dtr lay pvflag))

;; Guided sport bottom: plan hopper (standard-hopper dim logic) plus
;; the side profile below with C and D only.  Returns report rows.
;; G = 0 means no hopper pad (V bottom): the deep flat collapses to
;; the single V line, its residual splits across F2/F1, and the G
;; dim/report row are skipped -- the old NOhopper variant, now just a
;; zero answer at the G prompt.
(defun pool:hopsport (lline rline bline tline cen total x0 y0 ymax doff th
                      / wid whn hdn ggn pv e2r f2r gr f1r e1r mraw lraw kraw
                        wh hd res resid e2 f2 g f1 e1 m l k vres gg rows odl
                        brks tl xd nopad cv hfx vfx ans)
  (setq wid (distance (pool:linex cen (cadr lline) (car bline) (cadr bline))
                      (pool:linex cen (cadr lline) (car tline) (cadr tline)))
        whn (* 0.25 wid)
        hdn (* 0.55 wid))
  ;; nominal guide: plan + profile (padded proportions -- whether the
  ;; pool has a pad is only known once G is answered)
  (setq ggn (pool:hopsportc lline rline bline tline cen
                            (* 0.12 total) (* 0.20 total) (* 0.30 total)
                            (* 0.26 total) (* 0.12 total)
                            (* 0.2 wid) (* 0.2 wid)))
  (pool:hopsportdraw ggn nil "POOL-NOTES" t)
  (pool:profdraw x0 y0 total whn
                 (list (cons (* 0.12 total) whn)
                       (cons (* 0.32 total) hdn)
                       (cons (* 0.62 total) hdn)
                       (cons (* 0.88 total) whn))
                 "POOL-NOTES" t)
  (setq pv (append
    (list (pool:pvtie (cadr (assoc 'pl ggn)) (cadr (assoc 'pobl ggn)) "E2" th)
          (pool:pvtie (cadr (assoc 'pobl ggn)) (cadr (assoc 'pdfl ggn)) "F2" th)
          (pool:pvtie (cadr (assoc 'pdfl ggn)) (cadr (assoc 'pdfr ggn)) "G" th)
          (pool:pvtie (cadr (assoc 'pdfr ggn)) (cadr (assoc 'pobr ggn)) "F1" th)
          (pool:pvtie (cadr (assoc 'pobr ggn)) (cadr (assoc 'pr ggn)) "E1" th)
          (pool:pvtie (cadr (assoc 'pdt ggn)) (cadr (assoc 'pt ggn)) "M" th)
          (pool:pvtie (cadr (assoc 'pdb ggn)) (cadr (assoc 'pdt ggn)) "L" th)
          (pool:pvtie (cadr (assoc 'pb ggn)) (cadr (assoc 'pdb ggn)) "K" th)
          (pool:pvtie (list (+ x0 total (* 0.6 doff)) y0)
                      (list (+ x0 total (* 0.6 doff)) (- y0 whn)) "C" th)
          (pool:pvtie (list (+ x0 (* 0.5 total)) y0)
                      (list (+ x0 (* 0.5 total)) (- y0 hdn)) "D" th))))
  (command "_.ZOOM" "_Window"
           (pool:wp (list (- x0 doff) (- y0 hdn (* 3.0 doff))))
           (pool:wp (list (+ x0 total (* 3.0 doff)) (+ ymax doff))))
  (princ "\nSport bottom -- plan hopper letters; the RED tie is being asked for.")
  (princ "\n(after the first answer, Back re-asks the previous one)")
  (setq ans (pool:askseq
              (list (list 'e2 'NAX "E2 - left end shallow flat" (cdr (assoc "E2" pv)))
                    (list 'f2 'NAX "F2 - left slope" (cdr (assoc "F2" pv)))
                    (list 'g 'ZER "G - deep flat length, 0 = no hopper pad"
                          (cdr (assoc "G" pv)))
                    (list 'f1 'NAX "F1 - right slope" (cdr (assoc "F1" pv)))
                    (list 'e1 'NAX "E1 - right end shallow flat" (cdr (assoc "E1" pv)))
                    (list 'm 'NAX "M - top side to deep flat" (cdr (assoc "M" pv)))
                    (list 'l 'NAX "L - deep flat width" (cdr (assoc "L" pv)))
                    (list 'k 'SUG "K - deep flat to bottom side"
                          (cdr (assoc "K" pv)) '(m))))
        e2r (pool:sq ans 'e2) f2r (pool:sq ans 'f2) gr (pool:sq ans 'g)
        f1r (pool:sq ans 'f1) e1r (pool:sq ans 'e1)
        mraw (pool:sq ans 'm) lraw (pool:sq ans 'l) kraw (pool:sq ans 'k)
        nopad (and gr (< gr 1.0e-6))
        wh (pool:askh "C - wall height (shallow depth)" (cdr (assoc "C" pv)))
        hd (pool:askdeep "D - deep depth" (cdr (assoc "D" pv)) wh))
  (pool:pvkill)
  ;; resolve: horizontal chain vs the pool length (G absorbs; the
  ;; no-pad sport fixes G = 0 and splits its residual across F2/F1),
  ;; vertical chain vs the width (L absorbs)
  (if nopad
      (progn
        (setq res (pool:chainfix (list e2r f2r f1r e1r) total -1)
              e2 (car res) f2 (cadr res) f1 (caddr res) e1 (cadddr res)
              g 0.0
              resid (- total e2 f2 f1 e1))
        (if (> (abs resid) 1.0e-6)
            (setq f2 (+ f2 (* 0.5 resid))
                  f1 (+ f1 (* 0.5 resid)))))
      (setq res (pool:chainfix (list e2r f2r gr f1r e1r) total 2)
            e2 (car res) f2 (cadr res) g (caddr res)
            f1 (cadddr res) e1 (nth 4 res)))
  ;; no member of the resolved chain may be negative: floor it and
  ;; trim the largest other member, marking both red below
  (setq cv (pool:chainval (list e2 f2 g f1 e1) total)
        hfx (cadr cv)
        e2 (nth 0 (car cv)) f2 (nth 1 (car cv)) g (nth 2 (car cv))
        f1 (nth 3 (car cv)) e1 (nth 4 (car cv)))
  (if hfx (pool:valnote (strcat "SPORT LENGTHS FAILED - "
                                (pool:fixnames hfx '("E2" "F2" "G" "F1" "E1"))
                                " ADJUSTED, VERIFY")))
  ;; a G that resolves away (NA with the rest filling the length, or
  ;; absorbed to nothing) also collapses to the no-pad V bottom
  (if (< g 1.0e-6) (setq nopad t g 0.0))
  (setq vres (pool:chainfix (list mraw lraw kraw) wid 1)
        cv (pool:chainval vres wid) vres (car cv) vfx (cadr cv)
        m (car vres) l (cadr vres) k (caddr vres)
        gg (pool:hopsportc lline rline bline tline cen e2 f2 g f1 e1 m k))
  (if vfx (pool:valnote (strcat "SPORT WIDTHS FAILED - "
                                (pool:fixnames vfx '("M" "L" "K"))
                                " ADJUSTED, VERIFY")))
  (pool:hopsportdraw gg nopad "POOL" nil)
  ;; profile below, with C and D dims only
  (setq brks (if nopad
                 (list (cons e2 wh) (cons (+ e2 f2) hd) (cons (- total e1) wh))
                 (list (cons e2 wh) (cons (+ e2 f2) hd)
                       (cons (- total e1 f1) hd) (cons (- total e1) wh))))
  (pool:profdraw x0 y0 total wh brks "POOL" nil)
  (setq odl (getvar "CLAYER"))
  (setvar "CLAYER" "DIMENSION")
  ;; plan chains, standard-hopper style
  (foreach tl (append (list (list 'pl 'pobl nil (member 0 hfx))
                            (list 'pobl 'pdfl nil (member 1 hfx)))
                      (if nopad nil (list (list 'pdfl 'pdfr nil (member 2 hfx))))
                      (list (list 'pdfr 'pobr nil (member 3 hfx))
                            (list 'pobr 'pr nil (member 4 hfx))
                            (list 'pdt 'pt t (member 0 vfx))
                            (list 'pdb 'pdt t (member 1 vfx))
                            (list 'pb 'pdb t (member 2 vfx))))
    (pool:dimalg (cadr (assoc (car tl) gg)) (cadr (assoc (cadr tl) gg))
                 (pool:v+ (pool:mid (cadr (assoc (car tl) gg))
                                    (cadr (assoc (cadr tl) gg)))
                          (if (caddr tl) (cadr (assoc 'voff gg))
                              (list 0.0 0.0))))
    (if (cadddr tl) (pool:dimred)))
  (pool:dimalg (list (+ x0 total) y0) (list (+ x0 total) (- y0 wh))
               (list (+ x0 total (* 0.8 doff)) (- y0 (* 0.5 wh))))
  (setq xd (if nopad (+ x0 e2 f2) (+ x0 e2 f2 (* 0.5 g))))
  (pool:dimalg (list xd y0) (list xd (- y0 hd))
               (list (+ xd (* 0.3 doff)) (- y0 (* 0.5 hd))))
  (setvar "CLAYER" odl)
  (setq rows (append
    (list (pool:vrow "SPT E2" e2r (distance (cadr (assoc 'pl gg)) (cadr (assoc 'pobl gg))) 0 hfx)
          (pool:vrow "SPT F2" f2r (distance (cadr (assoc 'pobl gg)) (cadr (assoc 'pdfl gg))) 1 hfx))
    (if nopad nil
        (list (pool:vrow "SPT G" gr (distance (cadr (assoc 'pdfl gg)) (cadr (assoc 'pdfr gg))) 2 hfx)))
    (list (pool:vrow "SPT F1" f1r (distance (cadr (assoc 'pdfr gg)) (cadr (assoc 'pobr gg))) 3 hfx)
          (pool:vrow "SPT E1" e1r (distance (cadr (assoc 'pobr gg)) (cadr (assoc 'pr gg))) 4 hfx)
          (pool:vrow "SPT M" mraw (distance (cadr (assoc 'pdt gg)) (cadr (assoc 'pt gg))) 0 vfx)
          (pool:vrow "SPT L" lraw (distance (cadr (assoc 'pdb gg)) (cadr (assoc 'pdt gg))) 1 vfx)
          (pool:vrow "SPT K" kraw (distance (cadr (assoc 'pb gg)) (cadr (assoc 'pdb gg))) 2 vfx)
          (list "WALL HT C" wh wh)
          (list "DEPTH D" hd hd))))
  rows)

;; Pool-bottom dispatcher for the rectangle.
;; Returns the report rows (nil if skipped).
(defun pool:hopper (quad corners doff th / btype xmin xmax ymin ymax
                                           a b c d cen sres ln xi)
  (if (not (pool:askyn "Add pool bottom (hopper) detail?" "Yes" nil))
      nil
      (progn
        (setq xmin (apply 'min (mapcar 'car quad))
              xmax (apply 'max (mapcar 'car quad))
              ymin (apply 'min (mapcar 'cadr quad))
              ymax (apply 'max (mapcar 'cadr quad)))
        (command "_.ZOOM" "_Window"
                 (pool:wp (list (- xmin doff) (- ymin doff)))
                 (pool:wp (list (+ xmax doff) (+ ymax doff))))
        (setq btype (pool:askkw "Bottom type" pool:*btypes* pool:*btshown*
                                "Normal" nil))
        (if (/= btype "Sport")
            (pool:hopnormal quad corners doff th nil btype
                            xmin (- ymin (* 2.2 doff)) t)
            (progn
              (setq a (car quad) b (cadr quad) c (caddr quad) d (cadddr quad)
                    cen (pool:v* (pool:v+ (pool:v+ a b) (pool:v+ c d)) 0.25))
              (pool:hopsport (list a (pool:v- d a)) (list b (pool:v- c b))
                             (list a (pool:v- b a)) (list d (pool:v- c d))
                             cen (distance a b)
                             xmin (- ymin (* 2.2 doff)) ymax
                             doff th))))))

;;; -------------------- side profile -----------------------------------
;;;
;;;  Section view under the plan: waterline across the top, walls of
;;;  height C at both ends, and the bottom running through the given
;;;  break vertices.  Used by the normal hoppers and by the Sport
;;;  bottoms (whose field sheets ARE this profile).

;; Draw the profile outline.  x0/y0 = top-left, total = pool length,
;; wh = wall height, brks = bottom vertices ((dist . depth) ...) from
;; the left wall, left to right.
(defun pool:profdraw (x0 y0 total wh brks lay pvflag / pts prev p)
  (setq pts (append (list (list x0 y0)
                          (list (+ x0 total) y0)
                          (list (+ x0 total) (- y0 wh)))
                    (mapcar '(lambda (p) (list (+ x0 (car p)) (- y0 (cdr p))))
                            (reverse brks))
                    (list (list x0 (- y0 wh))
                          (list x0 y0)))
        prev (car pts))
  (foreach p (cdr pts)
    ;; a break sitting exactly on a wall bottom repeats that point
    (if (> (distance prev p) 1.0e-6)
        (progn
          (pool:hgl prev p lay pvflag)
          ;; remember the real (non-preview) section lines so an L
          ;; pool's plan mirror can leave them alone
          (if (not pvflag)
              (setq pool:*profents* (cons (entlast) pool:*profents*)))))
    (setq prev p)))

;; Dashed lettered guide tie from p to q; returns the (lbl ent...)
;; highlight assoc entry.
(defun pool:pvtie (p q lbl th / e et)
  (setq e (pool:pvadd (pool:pvlined p q)))
  (pool:text (pool:v+ (pool:mid p q) (list (* 0.5 th) (* 0.5 th)))
             (* 1.2 th) lbl "POOL-NOTES")
  (setq et (pool:pvadd (pool:setcol (entlast) pool:*pv-col*)))
  ;; the tie AND its letter highlight together while it is prompted
  (cons lbl (list e et)))

;; Line/arc makers used by the shape-specific hopper draws: when
;; pvflag is set they draw tracked gray guide entities instead.
(defun pool:hgl (p q lay pvflag)
  (if pvflag
      (pool:pvadd (pool:pvline p q))
      (pool:line p q lay)))

(defun pool:hga (p mm q lay pvflag)
  (if pvflag
      (progn
        (pool:arc3p p mm q "POOL-NOTES")
        (pool:pvadd (pool:setcol (entlast) pool:*pv-col*)))
      (pool:arc3p p mm q lay)))

;;; ---------------- oval pool bottom (True Oval sheet) -----------------
;;;
;;;  The hopper is a box with a radius (R3) left end, set out along
;;;  the pool axis (arc tip to arc tip):
;;;    H = pool left tip -> hopper tip      E = break -> pool right tip
;;;    G = hopper tip -> hopper right edge  M/K = top/bottom offsets
;;;    R3 = hopper end radius               L = hopper width (CHECK)
;;;    W = hopper flat top, tangent -> right edge (CHECK, = G - R3)
;;;    F = hopper -> slope break (CHECK)    T = straight side (CHECK)
;;;  No left ties (the radius IS the end); the right corners tie to
;;;  the slope-break ends as usual.

(defun pool:hopovalc (quad tipl tipr h g e m k r3 / a b c d cen u v ht hb
                                                    lt re tan brk tt tb tip vc
                                                    tip2)
  (setq a (car quad) b (cadr quad) c (caddr quad) d (cadddr quad)
        cen (pool:v* (pool:v+ (pool:v+ a b) (pool:v+ c d)) 0.25)
        u (pool:unit (pool:v- tipr tipl))
        v (pool:perp u)
        ht (pool:offline d c cen m)
        hb (pool:offline a b cen k)
        lt (list (pool:v+ tipl (pool:v* u h)) v)
        re (list (pool:v+ tipl (pool:v* u (+ h g))) v)
        tan (list (pool:v+ tipl (pool:v* u (+ h r3))) v)
        brk (list (pool:v- tipr (pool:v* u e)) v)
        tt (pool:linex (car tan) (cadr tan) (car ht) (cadr ht))
        tb (pool:linex (car tan) (cadr tan) (car hb) (cadr hb))
        tip (pool:mid (pool:linex (car lt) (cadr lt) (car ht) (cadr ht))
                      (pool:linex (car lt) (cadr lt) (car hb) (cadr hb)))
        ;; M/L/K attach to the hopper's right edge; dim line +12"
        vc (pool:v+ tipl (pool:v* u (+ h g)))
        ;; H/G/F/E chain below the hopper centre by 12" or L/6,
        ;; whichever is closer
        tip2 (pool:v- tip
                      (pool:v* (pool:unit v)
                               (min 12.0
                                    (/ (distance
                                         (pool:linex vc v (car hb) (cadr hb))
                                         (pool:linex vc v (car ht) (cadr ht)))
                                       6.0)))))
  (list (list 'tip tip) (list 'ttop tt) (list 'tbot tb)
        (list 'htr (pool:linex (car re) (cadr re) (car ht) (cadr ht)))
        (list 'hbr (pool:linex (car re) (cadr re) (car hb) (cadr hb)))
        (list 'brkb (pool:linex (car brk) (cadr brk) a (pool:v- b a)))
        (list 'brkt (pool:linex (car brk) (cadr brk) d (pool:v- c d)))
        (list 'ptan (pool:linex tip2 u (car tan) v))
        (list 'pl (pool:linex tip2 u tipl v))
        (list 'phl (pool:linex tip2 u (car lt) (cadr lt)))
        (list 'phr (pool:linex tip2 u (car re) v))
        (list 'pbrk (pool:linex tip2 u (car brk) v))
        (list 'pr (pool:linex tip2 u tipr v))
        (list 'pb (pool:linex vc v a (pool:v- b a)))
        (list 'phb (pool:linex vc v (car hb) (cadr hb)))
        (list 'pht (pool:linex vc v (car ht) (cadr ht)))
        (list 'pt (pool:linex vc v d (pool:v- c d)))
        (list 'voff (pool:v* u pool:*mlkoff*))))

(defun pool:hopovaldraw (gg lay pvflag / tt tb tip htr hbr brkb brkt)
  (setq tt (cadr (assoc 'ttop gg)) tb (cadr (assoc 'tbot gg))
        tip (cadr (assoc 'tip gg))
        htr (cadr (assoc 'htr gg)) hbr (cadr (assoc 'hbr gg))
        brkb (cadr (assoc 'brkb gg)) brkt (cadr (assoc 'brkt gg)))
  (pool:hgl tt htr lay pvflag)
  (pool:hgl tb hbr lay pvflag)
  (pool:hgl htr hbr lay pvflag)
  (pool:hga tt tip tb lay pvflag)
  (pool:hgl brkb brkt lay pvflag)
  (pool:hgl htr brkt lay pvflag)
  (pool:hgl hbr brkb lay pvflag))

;; Guided oval bottom phase.  Returns report rows (nil if skipped).
(defun pool:hopoval (quad tipl tipr doff th / len wid ggn pv gg rows tl odl
                                              h g f e m l k r3 r3raw w tt o
                                              hraw graw fraw eraw mraw lraw kraw
                                              totv hres vres cv hfx vfx r3wbad
                                              ans xmin xmax ymin ymax)
  (if nil                               ; Yes/No now lives in the dispatcher
      nil
      (progn
        (setq xmin (- (min (car tipl) (car tipr)) doff)
              xmax (+ (max (car tipl) (car tipr)) doff)
              ymin (- (apply 'min (mapcar 'cadr quad)) doff)
              ymax (+ (apply 'max (mapcar 'cadr quad)) doff))
        (command "_.ZOOM" "_Window" (pool:wp (list xmin ymin))
                 (pool:wp (list xmax ymax)))
        ;; nominal guide
        (setq len (distance tipl tipr)
              wid (distance (car quad) (cadddr quad))
              ggn (pool:hopovalc quad tipl tipr (* 0.10 len) (* 0.24 len)
                                 (* 0.38 len) (* 0.25 wid) (* 0.25 wid)
                                 (* 0.20 wid)))
        (pool:hopovaldraw ggn "POOL-NOTES" t)
        (setq pv (list
          (pool:pvtie (cadr (assoc 'pl ggn)) (cadr (assoc 'phl ggn)) "H" th)
          (pool:pvtie (cadr (assoc 'phl ggn)) (cadr (assoc 'phr ggn)) "G" th)
          (pool:pvtie (cadr (assoc 'phl ggn)) (cadr (assoc 'ptan ggn)) "R3" th)
          (pool:pvtie (cadr (assoc 'ttop ggn)) (cadr (assoc 'htr ggn)) "W" th)
          (pool:pvtie (cadr (assoc 'phr ggn)) (cadr (assoc 'pbrk ggn)) "F" th)
          (pool:pvtie (cadr (assoc 'pbrk ggn)) (cadr (assoc 'pr ggn)) "E" th)
          (pool:pvtie (cadr (assoc 'pht ggn)) (cadr (assoc 'pt ggn)) "M" th)
          (pool:pvtie (cadr (assoc 'phb ggn)) (cadr (assoc 'pht ggn)) "L" th)
          (pool:pvtie (cadr (assoc 'pb ggn)) (cadr (assoc 'phb ggn)) "K" th)
          (pool:pvtie (cadddr quad) (caddr quad) "T" th)))
        (princ "\nPool bottom -- offsets along the pool axis; the RED tie is being asked for.")
        (princ "\n(after the first answer, Back re-asks the previous one)")
        (setq ans (pool:askseq
                    (list (list 'h 'NAX "H - pool left tip to hopper tip" (cdr (assoc "H" pv)))
                          (list 'g 'NAX "G - hopper length (tip to right edge)" (cdr (assoc "G" pv)))
                          (list 'r3 'NAX "R3 - hopper end radius" (cdr (assoc "R3" pv)))
                          (list 'w 'NAX "W - hopper flat top" (cdr (assoc "W" pv)))
                          (list 'f 'NAX "F - hopper to slope break" (cdr (assoc "F" pv)))
                          (list 'e 'NAX "E - slope break to pool right tip" (cdr (assoc "E" pv)))
                          (list 'm 'SUG "M - top side to hopper" (cdr (assoc "M" pv)) '(h))
                          (list 'l 'NAX "L - hopper width" (cdr (assoc "L" pv)))
                          (list 'k 'SUG "K - hopper to bottom side" (cdr (assoc "K" pv)) '(m h))
                          (list 'tt 'NAX "T - straight side length (check)" (cdr (assoc "T" pv)))))
              hraw (pool:sq ans 'h) graw (pool:sq ans 'g) r3raw (pool:sq ans 'r3)
              w (pool:sq ans 'w) fraw (pool:sq ans 'f) eraw (pool:sq ans 'e)
              mraw (pool:sq ans 'm) lraw (pool:sq ans 'l) kraw (pool:sq ans 'k)
              tt (pool:sq ans 'tt))
        (pool:pvkill)
        ;; resolve against tip-to-tip length and side-to-side width
        (setq totv (distance
                     (pool:linex (pool:mid (car quad) (caddr quad))
                                 (pool:v- (cadddr quad) (car quad))
                                 (car quad) (pool:v- (cadr quad) (car quad)))
                     (pool:linex (pool:mid (car quad) (caddr quad))
                                 (pool:v- (cadddr quad) (car quad))
                                 (cadddr quad) (pool:v- (caddr quad) (cadddr quad))))
              hres (pool:chainfix (list hraw graw fraw eraw) (distance tipl tipr) 1)
              vres (pool:chainfix (list mraw lraw kraw) totv 1)
              cv (pool:chainval hres (distance tipl tipr))
              hres (car cv) hfx (cadr cv)
              cv (pool:chainval vres totv) vres (car cv) vfx (cadr cv)
              h (car hres) g (cadr hres) f (caddr hres) e (cadddr hres)
              m (car vres) l (cadr vres) k (caddr vres))
        (if hfx (pool:valnote (strcat "BOTTOM LENGTHS FAILED - "
                                      (pool:fixnames hfx '("H" "G" "F" "E"))
                                      " ADJUSTED, VERIFY")))
        (if vfx (pool:valnote (strcat "BOTTOM WIDTHS FAILED - "
                                      (pool:fixnames vfx '("M" "L" "K"))
                                      " ADJUSTED, VERIFY")))
        ;; The hopper's radius end and its flat top close against the
        ;; hopper length:  R3 + W = G.
        ;;   * R3 NA -> half the hopper width the offsets give (L/2),
        ;;     the semicircle end that meets the straight sides
        ;;     tangentially; failing that, whatever W leaves of G
        ;;   * W NA  -> G - R3, i.e. the flat runs from the arc's
        ;;     tangent point to the hopper's right edge
        (setq r3 (cond (r3raw r3raw)
                       ((> l 1.0e-6) (* 0.5 l))
                       (w (- g w))
                       (t (* 0.5 l))))
        (if (< r3 1.0e-6) (setq r3 (* 0.5 l)))
        ;; when BOTH were measured they must close against the hopper
        ;; length: R3 + W = G
        (if (and r3raw w (> (abs (- (+ r3raw w) g)) 0.5))
            (progn
              (setq r3wbad t)
              (pool:valnote "OVAL HOPPER R3 + W DOES NOT CLOSE AGAINST G - VERIFY")))
        (setq gg (pool:hopovalc quad tipl tipr h g e m k r3))
        (pool:hopovaldraw gg "POOL" nil)
        (setq odl (getvar "CLAYER"))
        (setvar "CLAYER" "DIMENSION")
        (foreach tl (list (list 'pl 'phl nil (member 0 hfx))
                          (list 'phl 'phr nil (member 1 hfx))
                          (list 'phr 'pbrk nil (member 2 hfx))
                          (list 'pbrk 'pr nil (member 3 hfx))
                          (list 'phl 'ptan nil r3wbad)
                          (list 'ttop 'htr nil r3wbad)
                          (list 'pht 'pt t (member 0 vfx))
                          (list 'phb 'pht t (member 1 vfx))
                          (list 'pb 'phb t (member 2 vfx)))
          (pool:dimalg (cadr (assoc (car tl) gg)) (cadr (assoc (cadr tl) gg))
                       (pool:v+ (pool:mid (cadr (assoc (car tl) gg))
                                          (cadr (assoc (cadr tl) gg)))
                                (if (caddr tl) (cadr (assoc 'voff gg))
                                    (list 0.0 0.0))))
          (if (cadddr tl) (pool:dimred)))
        (setvar "CLAYER" odl)
        (setq o (pool:circum (cadr (assoc 'ttop gg)) (cadr (assoc 'tip gg))
                             (cadr (assoc 'tbot gg)))
              rows (list
          (pool:vrow "HOP H" hraw (distance (cadr (assoc 'pl gg)) (cadr (assoc 'phl gg))) 0 hfx)
          (pool:vrow "HOP G" graw (distance (cadr (assoc 'phl gg)) (cadr (assoc 'phr gg))) 1 hfx)
          (append (list "HOP R3" r3raw (if o (distance o (cadr (assoc 'tip gg))) r3))
                  (if r3wbad (list t) nil))
          (append (list "HOP W" w (distance (cadr (assoc 'ttop gg)) (cadr (assoc 'htr gg))))
                  (if r3wbad (list t) nil))
          (pool:vrow "HOP F" fraw (distance (cadr (assoc 'phr gg)) (cadr (assoc 'pbrk gg))) 2 hfx)
          (pool:vrow "HOP E" eraw (distance (cadr (assoc 'pbrk gg)) (cadr (assoc 'pr gg))) 3 hfx)
          (pool:vrow "HOP M" mraw (distance (cadr (assoc 'pht gg)) (cadr (assoc 'pt gg))) 0 vfx)
          (pool:vrow "HOP L" lraw (distance (cadr (assoc 'phb gg)) (cadr (assoc 'pht gg))) 1 vfx)
          (pool:vrow "HOP K" kraw (distance (cadr (assoc 'pb gg)) (cadr (assoc 'phb gg))) 2 vfx)
          (list "HOP T" tt (distance (cadddr quad) (caddr quad)))))
        rows)))

;;; ---------------- grecian pool bottom (Square / 6-sided) -------------
;;;
;;;  Square hopper = the rectangle letters (H G F E M L K), anchored
;;;  off the end walls; each hopper left corner ties to BOTH ends of
;;;  its pool corner cut.  The 6-sided hopper cuts the deep pad's left
;;;  corners, and can be measured TWO ways (hex argument):
;;;
;;;    ("Offsets" co) -- offsets from the walls only: every pad edge
;;;      is its pool wall offset inward (left wall by H, top/bottom by
;;;      M/K) and the cut faces are the pool CORNER CUTS offset in by
;;;      co, so every hopper line is PARALLEL to its wall.  Corners
;;;      land wherever adjacent offset lines intersect.
;;;
;;;    ("Letters" w l1 lw) -- the field-sheet letters:
;;;      W  = the top/bottom flat, cut corner to the pad's right edge
;;;      L1 = the left edge length, centred on the pad
;;;      (lw = the resolved hopper width L, so the cut drop per corner
;;;      is (L - L1)/2; X = sqrt((G-W)^2 + ((L-L1)/2)^2) is a CHECK.)
;;;      The flats and the left edge ride their wall-offset lines
;;;      (parallel); the cut faces just CONNECT the corners and need
;;;      not be parallel to anything.
;;;
;;;  Either way the pool cut ends tie to the matching hopper corners.

(defun pool:hopgrecc (pts h g e m k hex / aa bb rb rt cc dd ltp lbp cen p
                                          hl hr ht hb brk hbl htl hbr htr
                                          hlw htl1 hbl1 hc u v hc2 out
                                          tcut bcut dy ct1 ct2 cb1 cb2)
  (setq aa (nth 0 pts) bb (nth 1 pts) rb (nth 2 pts) rt (nth 3 pts)
        cc (nth 4 pts) dd (nth 5 pts) ltp (nth 6 pts) lbp (nth 7 pts)
        cen (list 0.0 0.0))
  (foreach p pts (setq cen (pool:v+ cen p)))
  (setq cen (pool:v* cen 0.125)
        hl (pool:offline lbp ltp cen h)
        hr (pool:offline lbp ltp cen (+ h g))
        ht (pool:offline dd cc cen m)
        hb (pool:offline aa bb cen k)
        brk (pool:offline rb rt cen e)
        hbl (pool:linex (car hl) (cadr hl) (car hb) (cadr hb))
        htl (pool:linex (car hl) (cadr hl) (car ht) (cadr ht))
        hbr (pool:linex (car hr) (cadr hr) (car hb) (cadr hb))
        htr (pool:linex (car hr) (cadr hr) (car ht) (cadr ht))
        hc (pool:v* (pool:v+ (pool:v+ hbl htl) (pool:v+ hbr htr)) 0.25)
        u (pool:v- bb aa)
        v (pool:v- dd aa)
        ;; chain placement: H/G/F/E below the hopper centre by 12" or
        ;; L/6 (whichever is closer); M/L/K 12" right of the hopper
        hc2 (pool:v- hc (pool:v* (pool:unit v)
                                 (min 12.0 (/ (distance hbr htr) 6.0))))
        out (list
          (list 'hbl hbl) (list 'htl htl) (list 'hbr hbr) (list 'htr htr)
          (list 'brkb (pool:linex (car brk) (cadr brk) aa (pool:v- bb aa)))
          (list 'brkt (pool:linex (car brk) (cadr brk) dd (pool:v- cc dd)))
          (list 'aa aa) (list 'dd dd) (list 'ltp ltp) (list 'lbp lbp)
          (list 'pl (pool:linex hc2 u lbp (pool:v- ltp lbp)))
          (list 'phl (pool:linex hc2 u (car hl) (cadr hl)))
          (list 'phr (pool:linex hc2 u (car hr) (cadr hr)))
          (list 'pbrk (pool:linex hc2 u (car brk) (cadr brk)))
          (list 'pr (pool:linex hc2 u rb (pool:v- rt rb)))
          (list 'pb (pool:linex (car hr) (cadr hr) aa (pool:v- bb aa)))
          (list 'phb hbr)
          (list 'pht htr)
          (list 'pt (pool:linex (car hr) (cadr hr) dd (pool:v- cc dd)))
          (list 'voff (pool:v* (pool:unit u) pool:*mlkoff*))))
  (if hex
      (progn
        (if (= (car hex) "Offsets")
            ;; cut faces = the pool corner cuts offset inward by co;
            ;; corners at the intersections with the adjacent offsets
            (setq tcut (pool:offline ltp dd cen (cadr hex))
                  bcut (pool:offline lbp aa cen (cadr hex))
                  ct1 (pool:linex (car tcut) (cadr tcut) (car ht) (cadr ht))
                  ct2 (pool:linex (car tcut) (cadr tcut) (car hl) (cadr hl))
                  cb1 (pool:linex (car bcut) (cadr bcut) (car hb) (cadr hb))
                  cb2 (pool:linex (car bcut) (cadr bcut) (car hl) (cadr hl)))
            ;; sheet letters: cut corners W back from the pad's right
            ;; edge along the flats, the left edge L1 long centred on
            ;; the pad; the faces connect them (no parallelism forced)
            (setq hlw (pool:offline lbp ltp cen (+ h (- g (cadr hex))))
                  dy (* 0.5 (- (cadddr hex) (caddr hex)))
                  htl1 (pool:offline dd cc cen (+ m dy))
                  hbl1 (pool:offline aa bb cen (+ k dy))
                  ct1 (pool:linex (car hlw) (cadr hlw) (car ht) (cadr ht))
                  ct2 (pool:linex (car hl) (cadr hl) (car htl1) (cadr htl1))
                  cb1 (pool:linex (car hlw) (cadr hlw) (car hb) (cadr hb))
                  cb2 (pool:linex (car hl) (cadr hl) (car hbl1) (cadr hbl1))))
        (setq out (append out (list (list 'ct1 ct1) (list 'ct2 ct2)
                                    (list 'cb1 cb1) (list 'cb2 cb2))))))
  out)

(defun pool:hopgrecdraw (gg lay six pvflag / hbl htl hbr htr brkb brkt
                                             aa dd ltp lbp ct1 ct2 cb1 cb2)
  (setq hbl (cadr (assoc 'hbl gg)) htl (cadr (assoc 'htl gg))
        hbr (cadr (assoc 'hbr gg)) htr (cadr (assoc 'htr gg))
        brkb (cadr (assoc 'brkb gg)) brkt (cadr (assoc 'brkt gg))
        aa (cadr (assoc 'aa gg)) dd (cadr (assoc 'dd gg))
        ltp (cadr (assoc 'ltp gg)) lbp (cadr (assoc 'lbp gg)))
  (pool:hgl htr hbr lay pvflag)
  (pool:hgl brkb brkt lay pvflag)
  (pool:hgl htr brkt lay pvflag)
  (pool:hgl hbr brkb lay pvflag)
  (if six
      (progn
        (setq ct1 (cadr (assoc 'ct1 gg)) ct2 (cadr (assoc 'ct2 gg))
              cb1 (cadr (assoc 'cb1 gg)) cb2 (cadr (assoc 'cb2 gg)))
        (pool:hgl ct1 htr lay pvflag)
        (pool:hgl cb1 hbr lay pvflag)
        (pool:hgl ct2 cb2 lay pvflag)
        (pool:hgl ct2 ct1 lay pvflag)
        (pool:hgl cb2 cb1 lay pvflag)
        (pool:hgl dd ct1 lay pvflag)
        (pool:hgl ltp ct2 lay pvflag)
        (pool:hgl aa cb1 lay pvflag)
        (pool:hgl lbp cb2 lay pvflag))
      (progn
        (pool:hgl htl htr lay pvflag)
        (pool:hgl hbl hbr lay pvflag)
        (pool:hgl htl hbl lay pvflag)
        (pool:hgl dd htl lay pvflag)
        (pool:hgl ltp htl lay pvflag)
        (pool:hgl aa hbl lay pvflag)
        (pool:hgl lbp hbl lay pvflag))))

;; Guided grecian bottom phase.  Returns report rows (nil if skipped).
(defun pool:hopgrec (pts doff th / htype six mode len wid ggn pv gg rows tl odl
                                   h g f e m l k w l1 x co coraw xcal sixbad
                                   hraw graw fraw eraw mraw lraw kraw
                                   cen p u vv toth totv hres vres cv hfx vfx ans
                                   xmin xmax ymin ymax mm ud proj)
  (if nil                               ; Yes/No now lives in the dispatcher
      nil
      (progn
        (setq htype (pool:askkw "Hopper type" "Square SIX" "Square/SIX-sided"
                                "Square" nil)
              six (= htype "SIX"))
        ;; a six-sided deep end can be taped two ways: offsets shot
        ;; from every wall (cut faces parallel to the pool cuts), or
        ;; the sheet letters W / X / L / L1 / G / M / K
        (if six
            (setq mode (pool:askkw "SIX-sided corners measured by"
                                   "Offsets Letters" "Offsets/Letters"
                                   "Offsets" nil)))
        (setq xmin (- (apply 'min (mapcar 'car pts)) doff)
              xmax (+ (apply 'max (mapcar 'car pts)) doff)
              ymin (- (apply 'min (mapcar 'cadr pts)) doff)
              ymax (+ (apply 'max (mapcar 'cadr pts)) doff))
        (command "_.ZOOM" "_Window" (pool:wp (list xmin ymin))
                 (pool:wp (list xmax ymax)))
        ;; nominal guide
        (setq len (distance (nth 0 pts) (nth 1 pts))
              wid (distance (nth 0 pts) (nth 5 pts))
              ggn (pool:hopgrecc pts (* 0.10 len) (* 0.20 len) (* 0.38 len)
                                 (* 0.27 wid) (* 0.27 wid)
                                 (cond
                                   ((not six) nil)
                                   ((= mode "Offsets")
                                    (list "Offsets" (* 0.10 len)))
                                   (t (list "Letters" (* 0.12 len)
                                            (* 0.26 wid) (* 0.46 wid))))))
        (pool:hopgrecdraw ggn "POOL-NOTES" six t)
        (setq pv (list
          (pool:pvtie (cadr (assoc 'pl ggn)) (cadr (assoc 'phl ggn)) "H" th)
          (pool:pvtie (cadr (assoc 'phl ggn)) (cadr (assoc 'phr ggn)) "G" th)
          (pool:pvtie (cadr (assoc 'phr ggn)) (cadr (assoc 'pbrk ggn)) "F" th)
          (pool:pvtie (cadr (assoc 'pbrk ggn)) (cadr (assoc 'pr ggn)) "E" th)
          (pool:pvtie (cadr (assoc 'pht ggn)) (cadr (assoc 'pt ggn)) "M" th)
          (pool:pvtie (cadr (assoc 'phb ggn)) (cadr (assoc 'pht ggn)) "L" th)
          (pool:pvtie (cadr (assoc 'pb ggn)) (cadr (assoc 'phb ggn)) "K" th)))
        (if six
            (setq pv (append pv
              (if (= mode "Offsets")
                  (list (pool:pvtie
                          (pool:mid (cadr (assoc 'dd ggn)) (cadr (assoc 'ltp ggn)))
                          (pool:mid (cadr (assoc 'ct2 ggn)) (cadr (assoc 'ct1 ggn)))
                          "CUT" th))
                  (list (pool:pvtie (cadr (assoc 'ct1 ggn)) (cadr (assoc 'htr ggn))
                                    "W" th)
                        (pool:pvtie (cadr (assoc 'ct2 ggn)) (cadr (assoc 'cb2 ggn))
                                    "L1" th)
                        (pool:pvtie (cadr (assoc 'ct2 ggn)) (cadr (assoc 'ct1 ggn))
                                    "X" th))))))
        (princ "\nPool bottom -- offsets from the end walls; the RED tie is being asked for.")
        (princ "\n(after the first answer, Back re-asks the previous one)")
        (setq ans (pool:askseq
                    (append
                      (list (list 'h 'NAX "H - left end to hopper" (cdr (assoc "H" pv)))
                            (list 'g 'NAX "G - hopper length" (cdr (assoc "G" pv))))
                      (cond
                        ((not six) nil)
                        ((= mode "Offsets")
                         (list (list 'co 'NAX
                                     "Cut faces - offset in from the pool corner cuts (NA = H)"
                                     (cdr (assoc "CUT" pv)))))
                        (t
                         (list (list 'w 'REQ "W - top/bottom flat, cut corner to hopper end"
                                     (cdr (assoc "W" pv)))
                               (list 'l1 'REQ "L1 - hopper left edge length"
                                     (cdr (assoc "L1" pv)))
                               (list 'x 'NAX "X - hopper cut face length (check)"
                                     (cdr (assoc "X" pv))))))
                      (list (list 'f 'NAX "F - hopper to slope break" (cdr (assoc "F" pv)))
                            (list 'e 'NAX "E - slope break to right end" (cdr (assoc "E" pv)))
                            (list 'm 'SUG "M - top side to hopper" (cdr (assoc "M" pv)) '(h))
                            (list 'l 'NAX "L - hopper width" (cdr (assoc "L" pv)))
                            (list 'k 'SUG "K - hopper to bottom side"
                                  (cdr (assoc "K" pv)) '(m h)))))
              hraw (pool:sq ans 'h) graw (pool:sq ans 'g)
              coraw (pool:sq ans 'co)
              w (pool:sq ans 'w) l1 (pool:sq ans 'l1) x (pool:sq ans 'x)
              fraw (pool:sq ans 'f) eraw (pool:sq ans 'e)
              mraw (pool:sq ans 'm) lraw (pool:sq ans 'l) kraw (pool:sq ans 'k))
        (pool:pvkill)
        ;; resolve against wall-to-wall totals (end wall to end wall,
        ;; side to side) through the pool centre
        (setq cen (list 0.0 0.0))
        (foreach p pts (setq cen (pool:v+ cen p)))
        (setq cen (pool:v* cen 0.125)
              u (pool:v- (nth 1 pts) (nth 0 pts))
              vv (pool:v- (nth 5 pts) (nth 0 pts))
              toth (distance
                     (pool:linex cen u (nth 7 pts) (pool:v- (nth 6 pts) (nth 7 pts)))
                     (pool:linex cen u (nth 2 pts) (pool:v- (nth 3 pts) (nth 2 pts))))
              totv (distance
                     (pool:linex cen vv (nth 0 pts) (pool:v- (nth 1 pts) (nth 0 pts)))
                     (pool:linex cen vv (nth 5 pts) (pool:v- (nth 4 pts) (nth 5 pts))))
              hres (pool:chainfix (list hraw graw fraw eraw) toth 1)
              vres (pool:chainfix (list mraw lraw kraw) totv 1)
              cv (pool:chainval hres toth) hres (car cv) hfx (cadr cv)
              cv (pool:chainval vres totv) vres (car cv) vfx (cadr cv)
              h (car hres) g (cadr hres) f (caddr hres) e (cadddr hres)
              m (car vres) l (cadr vres) k (caddr vres))
        (if hfx (pool:valnote (strcat "BOTTOM LENGTHS FAILED - "
                                      (pool:fixnames hfx '("H" "G" "F" "E"))
                                      " ADJUSTED, VERIFY")))
        (if vfx (pool:valnote (strcat "BOTTOM WIDTHS FAILED - "
                                      (pool:fixnames vfx '("M" "L" "K"))
                                      " ADJUSTED, VERIFY")))
        ;; six-sided closure checks, per input method
        (if (and six (= mode "Offsets"))
            (setq co (if coraw coraw h)))
        (if (and six (= mode "Letters"))
            (progn
              (if (> w g)
                  (progn (setq w g sixbad t)
                         (pool:valnote "HOPPER W LONGER THAN G - ADJUSTED")))
              (if (> l1 l)
                  (progn (setq l1 l sixbad t)
                         (pool:valnote "HOPPER L1 LONGER THAN L - ADJUSTED")))
              (setq xcal (sqrt (+ (* (- g w) (- g w))
                                  (* (* 0.5 (- l l1)) (* 0.5 (- l l1))))))
              (if (and x (> (abs (- x xcal)) 0.5))
                  (progn (setq sixbad t)
                         (pool:valnote "HOPPER CUT X DOES NOT CLOSE AGAINST W/L1 - VERIFY")))))
        (setq gg (pool:hopgrecc pts h g e m k
                                (cond
                                  ((not six) nil)
                                  ((= mode "Offsets") (list "Offsets" co))
                                  (t (list "Letters" w l1 l)))))
        (pool:hopgrecdraw gg "POOL" six nil)
        (setq odl (getvar "CLAYER"))
        (setvar "CLAYER" "DIMENSION")
        (foreach tl (list (list 'pl 'phl nil (member 0 hfx))
                          (list 'phl 'phr nil (member 1 hfx))
                          (list 'phr 'pbrk nil (member 2 hfx))
                          (list 'pbrk 'pr nil (member 3 hfx))
                          (list 'pht 'pt t (member 0 vfx))
                          (list 'phb 'pht t (member 1 vfx))
                          (list 'pb 'phb t (member 2 vfx)))
          (pool:dimalg (cadr (assoc (car tl) gg)) (cadr (assoc (cadr tl) gg))
                       (pool:v+ (pool:mid (cadr (assoc (car tl) gg))
                                          (cadr (assoc (cadr tl) gg)))
                                (if (caddr tl) (cadr (assoc 'voff gg))
                                    (list 0.0 0.0))))
          (if (cadddr tl) (pool:dimred)))
        (if six
            (if (= mode "Offsets")
                ;; one offset dim per cut face, square off the pool cut
                (foreach tl (list (list 'ct1 'ct2 'dd 'ltp)
                                  (list 'cb1 'cb2 'aa 'lbp))
                  (setq mm (pool:mid (cadr (assoc (car tl) gg))
                                     (cadr (assoc (cadr tl) gg)))
                        ud (pool:unit (pool:v- (cadr (assoc (cadddr tl) gg))
                                               (cadr (assoc (caddr tl) gg))))
                        proj (pool:v+ (cadr (assoc (caddr tl) gg))
                                      (pool:v* ud (pool:dot
                                        (pool:v- mm (cadr (assoc (caddr tl) gg)))
                                        ud))))
                  (pool:dimalg proj mm (pool:mid proj mm))
                  (if sixbad (pool:dimred)))
                ;; the sheet letters: W flat, L1 left edge, X on a face
                (progn
                  (pool:dimalg (cadr (assoc 'ct1 gg)) (cadr (assoc 'htr gg))
                               (pool:mid (cadr (assoc 'ct1 gg)) (cadr (assoc 'htr gg))))
                  (if sixbad (pool:dimred))
                  (pool:dimalg (cadr (assoc 'ct2 gg)) (cadr (assoc 'cb2 gg))
                               (pool:mid (cadr (assoc 'ct2 gg)) (cadr (assoc 'cb2 gg))))
                  (if sixbad (pool:dimred))
                  (pool:dimalg (cadr (assoc 'cb2 gg)) (cadr (assoc 'cb1 gg))
                               (pool:mid (cadr (assoc 'cb2 gg)) (cadr (assoc 'cb1 gg))))
                  (if sixbad (pool:dimred)))))
        (setvar "CLAYER" odl)
        (setq rows (list
          (pool:vrow "HOP H" hraw (distance (cadr (assoc 'pl gg)) (cadr (assoc 'phl gg))) 0 hfx)
          (pool:vrow "HOP G" graw (distance (cadr (assoc 'phl gg)) (cadr (assoc 'phr gg))) 1 hfx)
          (pool:vrow "HOP F" fraw (distance (cadr (assoc 'phr gg)) (cadr (assoc 'pbrk gg))) 2 hfx)
          (pool:vrow "HOP E" eraw (distance (cadr (assoc 'pbrk gg)) (cadr (assoc 'pr gg))) 3 hfx)
          (pool:vrow "HOP M" mraw (distance (cadr (assoc 'pht gg)) (cadr (assoc 'pt gg))) 0 vfx)
          (pool:vrow "HOP L" lraw (distance (cadr (assoc 'phb gg)) (cadr (assoc 'pht gg))) 1 vfx)
          (pool:vrow "HOP K" kraw (distance (cadr (assoc 'pb gg)) (cadr (assoc 'phb gg))) 2 vfx)))
        (if six
            (setq rows (append rows
              (if (= mode "Offsets")
                  ;; actual = the drawn face's true perpendicular
                  ;; offset from the pool's corner cut
                  (progn
                    (setq mm (pool:mid (cadr (assoc 'ct2 gg)) (cadr (assoc 'ct1 gg)))
                          ud (pool:unit (pool:v- (cadr (assoc 'ltp gg))
                                                 (cadr (assoc 'dd gg))))
                          proj (pool:v+ (cadr (assoc 'dd gg))
                                        (pool:v* ud (pool:dot
                                          (pool:v- mm (cadr (assoc 'dd gg))) ud))))
                    (list (list "HOP CUT OFF" coraw (distance proj mm))))
                  (list
                    (append (list "HOP W" w (distance (cadr (assoc 'ct1 gg))
                                                      (cadr (assoc 'htr gg))))
                            (if sixbad (list t) nil))
                    (append (list "HOP L1" l1 (distance (cadr (assoc 'ct2 gg))
                                                        (cadr (assoc 'cb2 gg))))
                            (if sixbad (list t) nil))
                    (append (list "HOP X" x (distance (cadr (assoc 'ct2 gg))
                                                      (cadr (assoc 'ct1 gg))))
                            (if sixbad (list t) nil)))))))
        rows)))

;; Body quad spanning two end lines and the two side lines: the frame
;; the special bottoms measure their chain off for the shapes whose
;; ends are not plain corners.
(defun pool:bodyquad (lline rline bline tline)
  (list (pool:linex (car lline) (cadr lline) (car bline) (cadr bline))
        (pool:linex (car rline) (cadr rline) (car bline) (cadr bline))
        (pool:linex (car rline) (cadr rline) (car tline) (cadr tline))
        (pool:linex (car lline) (cadr lline) (car tline) (cadr tline))))

;; Bottom-type dispatchers for oval and grecian pools.  Normal keeps
;; each shape's own field sheet (radius end / corner cuts); the four
;; special bottoms are the standard chain measured off the body, so
;; they work here too.

(defun pool:hopovaldsp (quad tipl tipr doff th / btype u v sres p xi
                                                 lline rline bline tline)
  (if (not (pool:askyn "Add pool bottom (hopper) detail?" "Yes" nil))
      nil
      (progn
        (setq btype (pool:askkw "Bottom type" pool:*btypes* pool:*btshown*
                                "Normal" nil))
        (setq u (pool:unit (pool:v- tipr tipl))
              v (pool:perp u)
              lline (list tipl v)
              rline (list tipr v)
              bline (list (car quad) (pool:v- (cadr quad) (car quad)))
              tline (list (cadddr quad)
                          (pool:v- (caddr quad) (cadddr quad))))
        (cond
          ((= btype "Normal") (pool:hopoval quad tipl tipr doff th))
          ;; the oval's ends are arcs, so there are no left corners to
          ;; tie the deep end back to
          ((/= btype "Sport")
           (pool:hopnormal (pool:bodyquad lline rline bline tline)
                           pool:*sq4* doff th nil btype
                           (min (car tipl) (car tipr))
                           (- (apply 'min (mapcar 'cadr quad)) (* 2.2 doff))
                           nil))
          (t
            (pool:hopsport (list tipl v) (list tipr v)
                             (list (car quad) (pool:v- (cadr quad) (car quad)))
                             (list (cadddr quad)
                                   (pool:v- (caddr quad) (cadddr quad)))
                             (pool:v* (pool:v+ (pool:v+ (car quad) (cadr quad))
                                               (pool:v+ (caddr quad) (cadddr quad)))
                                      0.25)
                             (distance tipl tipr)
                             (min (car tipl) (car tipr))
                             (- (apply 'min (mapcar 'cadr quad)) (* 2.2 doff))
                             (apply 'max (mapcar 'cadr quad))
                             doff th))))))

(defun pool:hopgrecdsp (pts doff th / btype cen p u pl pr sres xi ln
                                      lline rline bline tline)
  (if (not (pool:askyn "Add pool bottom (hopper) detail?" "Yes" nil))
      nil
      (progn
        (setq btype (pool:askkw "Bottom type" pool:*btypes* pool:*btshown*
                                "Normal" nil))
        (setq cen (list 0.0 0.0))
        (foreach p pts (setq cen (pool:v+ cen p)))
        (setq cen (pool:v* cen 0.125)
              u (pool:v- (nth 1 pts) (nth 0 pts))
              lline (list (nth 7 pts) (pool:v- (nth 6 pts) (nth 7 pts)))
              rline (list (nth 2 pts) (pool:v- (nth 3 pts) (nth 2 pts)))
              bline (list (nth 0 pts) (pool:v- (nth 1 pts) (nth 0 pts)))
              tline (list (nth 5 pts) (pool:v- (nth 4 pts) (nth 5 pts)))
              pl (pool:linex cen u (car lline) (cadr lline))
              pr (pool:linex cen u (car rline) (cadr rline)))
        (cond
          ((= btype "Normal") (pool:hopgrec pts doff th))
          ((/= btype "Sport")
           ;; the deep end ties to BOTH ends of each left corner cut,
           ;; exactly as the Grecian's own hopper does
           (pool:hopnormal (pool:bodyquad lline rline bline tline)
                           (list (list "Ends" (nth 7 pts) (nth 0 pts))
                                 (list "Square" 0.0)
                                 (list "Square" 0.0)
                                 (list "Ends" (nth 5 pts) (nth 6 pts)))
                           doff th nil btype
                           (apply 'min (mapcar 'car pts))
                           (- (apply 'min (mapcar 'cadr pts)) (* 2.2 doff))
                           t))
          (t
            (pool:hopsport lline rline bline tline
                             cen (distance pl pr)
                             (apply 'min (mapcar 'car pts))
                             (- (apply 'min (mapcar 'cadr pts)) (* 2.2 doff))
                             (apply 'max (mapcar 'cadr pts))
                             doff th))))))

;;; -------------------- oval ends --------------------------------------
;;;
;;;  R1/R2 are TRUE arc radii: each end arc springs from the two end
;;;  corners (chord c = the end length) and bulges past them by the
;;;  sagitta  s = R - sqrt(R^2 - (c/2)^2).  Dimensioning the drawn arc
;;;  therefore reads back the radius that was typed in.

;; Bulge of an arc of radius r spanning a chord c.  An r smaller than
;; the chord's half cannot reach across it, so it is clamped to the
;; semicircle (the tightest arc that end can have).
(defun pool:sag (r c / half)
  (setq half (* 0.5 c))
  (if (<= r half) half (- r (sqrt (- (* r r) (* half half))))))

;; The inverse: radius of the arc that bulges s past a chord c.
(defun pool:sagr (s c / half)
  (setq half (* 0.5 c))
  (if (<= s 1.0e-9) nil (/ (+ (* s s) (* half half)) (* 2.0 s))))

;; Resolve the two end arcs against the overall length.  The overall
;; closes the chain  s_left + axis + s_right = TOTAL, so any one of
;; TOTAL / R1 / R2 may be NA:
;;   * both radii NA -> the remainder splits evenly between the ends,
;;     i.e. both arcs the same -- exactly what an in-square oval is;
;;   * one radius NA -> it takes the remainder;
;;   * TOTAL NA      -> it is computed from the two radii.
;; lc/rc are the end lengths (chords).  Returns (lrad rrad sl sr total notes).
(defun pool:ovalends (totl lraw rraw axis lc rc / sl sr left notes lr rr)
  (if (and lraw rraw)
      (setq sl (pool:sag lraw lc)
            sr (pool:sag rraw rc))
      (progn
        (setq left (- totl axis))       ; length left over for the ends
        (cond
          ((and (null lraw) (null rraw))
           (setq sl (* 0.5 left) sr (* 0.5 left)))
          ((null lraw)
           (setq sr (pool:sag rraw rc) sl (- left sr)))
          (t
           (setq sl (pool:sag lraw lc) sr (- left sl))))))
  ;; a bulge that came out at or below zero means the overall and the
  ;; body disagree; fall back to the semicircle and say so
  (if (<= sl 1.0e-6)
      (setq sl (* 0.5 lc)
            notes (cons "LEFT END DOES NOT FIT THE TOTAL LENGTH - SEMICIRCLE USED" notes)))
  (if (<= sr 1.0e-6)
      (setq sr (* 0.5 rc)
            notes (cons "RIGHT END DOES NOT FIT THE TOTAL LENGTH - SEMICIRCLE USED" notes)))
  ;; a radius tighter than the end is half its width was clamped above
  (if (and lraw (< lraw (- (* 0.5 lc) 1.0e-6)))
      (setq notes (cons "LEFT RADIUS SMALLER THAN HALF THE END - SEMICIRCLE USED" notes)))
  (if (and rraw (< rraw (- (* 0.5 rc) 1.0e-6)))
      (setq notes (cons "RIGHT RADIUS SMALLER THAN HALF THE END - SEMICIRCLE USED" notes)))
  (setq lr (pool:sagr sl lc)
        rr (pool:sagr sr rc))
  (list lr rr sl sr (+ sl axis sr) notes))

;;; -------------------- rectangle / oval flow --------------------------

;; Full guided flow for the quad-based pools: preview, prompts, fit,
;; draw, dimension and report.  Caller handles sysvars/undo/zoom.
(defun pool:quadflow (ptype / oldclay pv arcs
                             tp bo le ri dac dbd totl lrad rrad
                             corners cmode anycut cc prevty prevsz lbl
                             gq gcorners xmeas tm hl val m rpa rpb pass
                             ans xitems cc2
                             fitres quad failed a b c d cen meas notes tri
                             doff th endoff pr odim k
                             midl midr ml mr tipl tipr
                             ores lrfit rrfit larc rarc
                             allpts xmax ymax ymin rows)
  (setq oldclay (getvar "CLAYER"))

  ;; -------------------------------------- guide preview + input
  (setq pv (pool:preview ptype))
  (command "_.ZOOM" "_Window"
           (pool:wp (list -170.0 -60.0)) (pool:wp (list 530.0 240.0)))
  (princ "\nA gray guide pool is shown -- the RED element is the dimension being asked for.")
  (princ "\nCorners: A bottom-left, B bottom-right, C top-right, D top-left.")

  ;; in-square: opposing sides are equal, ask each pair once
  (princ "\n(Back re-asks the previous question, right back to the start)")
  (defun qf:sides ( / ans)
  (if pool:*insq*
      (setq ans (pool:askseqb
                  (list (list 'tp 'REQ "Side length (top & bottom)"
                              (append (cdr (assoc 'dc pv)) (cdr (assoc 'ab pv))
                                      (pool:lbl pv '(lA lB lC lD))))
                        (list 'le 'REQ "End length (left & right)"
                              (append (cdr (assoc 'da pv)) (cdr (assoc 'bc pv))
                                      (pool:lbl pv '(lA lB lC lD)))))
                  nil)
            tp (pool:sq ans 'tp) bo tp
            le (pool:sq ans 'le) ri le)
      (setq ans (pool:askseqb
                  (list (list 'tp 'REQ "Side length TOP (D-C)"
                              (append (cdr (assoc 'dc pv)) (pool:lbl pv '(lD lC))))
                        (list 'bo 'REQ "Side length BOTTOM (A-B)"
                              (append (cdr (assoc 'ab pv)) (pool:lbl pv '(lA lB))))
                        (list 'le 'REQ "End length LEFT (A-D)"
                              (append (cdr (assoc 'da pv)) (pool:lbl pv '(lA lD))))
                        (list 'ri 'REQ "End length RIGHT (B-C)"
                              (append (cdr (assoc 'bc pv)) (pool:lbl pv '(lB lC)))))
                  nil)
            tp (pool:sq ans 'tp) bo (pool:sq ans 'bo)
            le (pool:sq ans 'le) ri (pool:sq ans 'ri)))
    ans)

  ;; -------- oval ends.  Any ONE of total / left radius / right radius
  ;; may be NA -- the overall closes the chain against the body, and
  ;; with both radii NA the two ends come out the same (the in-square
  ;; oval).  Only the total is re-asked when too much is missing.
  (defun qf:oval ( / ans)
  (if (/= ptype "Oval")
      nil
      (progn
        ;; in-square ovals are symmetric, so the end radius is asked once
        (setq ans (pool:askseqb
                    (if pool:*insq*
                        (list (list 'tot 'NAX "Total pool length (arc tip to arc tip)"
                                    (cdr (assoc 'tot pv)))
                              (list 'lr 'NAX "End radius (both ends)"
                                    (append (cdr (assoc 'lrad pv))
                                            (cdr (assoc 'rrad pv)))))
                        (list (list 'tot 'NAX "Total pool length (arc tip to arc tip)"
                                    (cdr (assoc 'tot pv)))
                              (list 'lr 'NAX "LEFT oval end radius"
                                    (cdr (assoc 'lrad pv)))
                              (list 'rr 'NAX "RIGHT oval end radius"
                                    (cdr (assoc 'rrad pv)))))
                    t))
        (if (eq ans 'POOL-BACK)
            'POOL-BACK
            (progn
              (setq totl (pool:sq ans 'tot)
                    lrad (pool:sq ans 'lr)
                    rrad (if pool:*insq* lrad (pool:sq ans 'rr)))
              (if (and (null totl) (or (null lrad) (null rrad)))
                  (progn
                    (princ "\nThe total length is needed when an end radius is NA.")
                    (setq totl (pool:askh "Total pool length (arc tip to arc tip)"
                                          (cdr (assoc 'tot pv))))))
              nil)))))

  ;; -------- corner treatments (rectangle only; side lengths are to
  ;; the TRUE corner, treatments cut inward)
  (defun qf:corners ( / i lbls out back)
    (if (/= ptype "Rectangle")
        (progn
          (setq corners (list (list "Square" 0.0) (list "Square" 0.0)
                              (list "Square" 0.0) (list "Square" 0.0)))
          (qf:aftercorners)
          nil)
        (if pool:*insq*
            (progn                      ; in-square: one answer for all 4
              (setq cc (pool:askcorner "All corners (assumed identical)" nil nil
                                       (pool:lbl pv '(lA lB lC lD))
                                       (* 0.5 (min tp le)) nil t))
              (if (eq cc 'POOL-BACK)
                  'POOL-BACK
                  (progn (setq corners (list cc cc cc cc))
                         (qf:aftercorners)
                         nil)))
            (progn                      ; out-of-square: per corner, Enter reuses
              (princ "\n(per-corner treatment; press Enter to reuse the previous corner)")
              (setq lbls (list (list "A" bo le) (list "B" bo ri)
                               (list "C" tp ri) (list "D" tp le))
                    corners nil prevty nil prevsz nil i 0 back nil)
              (while (and (< i 4) (not back))
                (setq cc (pool:askcorner
                           (strcat "Corner " (car (nth i lbls))) prevty prevsz
                           (pool:lbl pv (list (pool:lblkey (car (nth i lbls)))))
                           (* 0.5 (min (cadr (nth i lbls)) (caddr (nth i lbls))))
                           nil t))
                (if (eq cc 'POOL-BACK)
                    (if (= i 0)
                        (setq back t)   ; back out of the whole stage
                        (setq i (1- i)
                              corners (cdr corners)
                              ;; the reuse default is the corner BEFORE
                              ;; the one being re-asked
                              prevty (if corners (car (car corners)) nil)
                              prevsz (if corners (cadr (car corners)) nil)))
                    (setq prevty (car cc) prevsz (cadr cc)
                          corners (cons cc corners)
                          i (1+ i))))
              (if back
                  'POOL-BACK
                  (progn (setq corners (reverse corners))
                         (qf:aftercorners)
                         nil))))))

  ;; everything the corner answers determine: the cut flag and the
  ;; guide redraw.  Re-runnable, so backing in and out is safe.
  (defun qf:aftercorners ( / c)
    (setq anycut nil)
    (foreach c corners (if (/= (car c) "Square") (setq anycut t)))
    (setq gq (list (list 0.0 0.0) (list 360.0 0.0)
                   (list 360.0 180.0) (list 0.0 180.0))
          gcorners (mapcar '(lambda (c) (list (car c) (min (cadr c) 60.0)))
                           corners))
    (if anycut (setq pv (pool:pvcorners pv gq gcorners)))
    (princ))

  ;; -------- cross-dim reference mode (only when corners are cut and
  ;; the pool is out-of-square)
  (defun qf:cmode ( / v)
    (setq cmode "Corner")
    (if (and (not pool:*insq*) anycut)
        (progn
          (setq v (pool:askkw "Cut corners -- cross dims measured from"
                              "Corner Middle Ends" "Corner/Middle/Ends" nil t))
          (if (eq v 'POOL-BACK) v (progn (setq cmode v) nil)))
        nil))

  ;; -------- cross dims (out-of-square only), per the reference mode.
  ;; The corner-to-corner guide diagonals are retired and one dashed
  ;; guide line is drawn per measurement between its actual reference
  ;; points, so Middle/Ends prompts highlight exactly what gets taped.
  (defun qf:cross ( / xg)
    (setq xmeas nil)
    (if pool:*insq*
        (progn
          (princ "\nIn-square: building true to the side measurements (no cross dims).")
          nil)
        (progn
          ;; sides are all in -- the cross dims appear now, one guide
          ;; line per measurement, between its actual reference points,
          ;; then the block runs as one Back-able sequence
          (setq xitems nil xg nil k 0)
          (foreach tm (pool:crosstemplate cmode)
            (setq rpa (pool:cornerpoint gq gcorners (nth 3 tm) (nth 4 tm))
                  rpb (pool:cornerpoint gq gcorners (nth 5 tm) (nth 6 tm))
                  hl (pool:pvadd (pool:pvlined rpa rpb))
                  xg (cons hl xg)
                  xitems (cons (list (read (strcat "x" (itoa k))) 'NAX (cadr tm)
                                     (cons hl (pool:lbl pv
                                       (list (pool:lblkey (nth (nth 3 tm) '("A" "B" "C" "D")))
                                             (pool:lblkey (nth (nth 5 tm) '("A" "B" "C" "D")))))))
                               xitems)
                  k (1+ k)))
          (setq ans (pool:askseqb (reverse xitems) t))
          (if (eq ans 'POOL-BACK)
              ;; drop this round's guide lines so a re-entry redraws
              ;; them cleanly for whatever mode is chosen next
              (progn (pool:pvdel xg) 'POOL-BACK)
              (progn
                (setq k 0)
                (foreach tm (pool:crosstemplate cmode)
                  (setq xmeas (cons (append tm
                                            (list (pool:sq ans (read (strcat "x" (itoa k))))))
                                    xmeas)
                        k (1+ k)))
                (setq xmeas (reverse xmeas))
                nil)))))

  ;; ---- the input phase, with Back working right across it
  (pool:stages (list 'qf:sides 'qf:oval 'qf:corners 'qf:cmode 'qf:cross))


  ;; the guide has served its purpose -- replace it with the true pool
  (pool:pvkill)

  ;; ------------------------------------------------ fit the body
  ;; bootstrap the true-corner cross targets from the raw measurements,
  ;; then (for cut corners) refine them against the fitted corner
  ;; reference points and re-fit.
  (princ "\nFitting pool body to the measurements ...")
  (setq dac (pool:rawavg xmeas 'ac)
        dbd (pool:rawavg xmeas 'bd)
        fitres (pool:fitquad bo tp le ri dac dbd pool:*side-tol* pool:*cross-tol*)
        quad (car fitres)
        failed (cadr fitres))
  (if (/= cmode "Corner")
      (progn
        (setq pass 0)
        (while (< pass 2)
          (setq dac (pool:effcross quad corners xmeas 'ac)
                dbd (pool:effcross quad corners xmeas 'bd)
                fitres (pool:fitquad bo tp le ri dac dbd pool:*side-tol* pool:*cross-tol*)
                quad (car fitres)
                failed (cadr fitres)
                pass (1+ pass)))))
  (setq a (car quad) b (cadr quad) c (caddr quad) d (cadddr quad)
        cen (pool:v* (pool:v+ (pool:v+ a b) (pool:v+ c d)) 0.25)
        meas (pool:quadmeas quad)
        notes nil)

  ;; dashed linetype + scale for the reference lines
  (setq pool:*dashlt* (pool:ltload "DASHED"))

  ;; -------------------------------- pool body / perimeter (layer POOL)
  ;; Rectangle draws its perimeter with corner treatments.  The oval's
  ;; end chords are construction, not pool, so only the two sides are
  ;; drawn and the perimeter closes through the end arcs.
  (if (= ptype "Rectangle")
      (setq arcs (pool:drawrect quad corners))
      (progn
        (pool:line a b "POOL")
        (pool:line c d "POOL")))

  ;; -------------------------------------- exact two-triangle check
  ;; Computed only (needs the A-C cross dim -- skipped when it was NA);
  ;; the result feeds the TRI CHECK B-D report row.  The check figure
  ;; itself is no longer drawn so out-of-square pools leave a clean
  ;; drawing behind.
  (setq tri (if dac (pool:triquad bo tp le ri dac) nil))
  (if (and dac (not tri))
      (setq notes (cons "TRIANGLE CHECK IMPOSSIBLE - VERIFY MEASUREMENTS" notes)))

  (setq doff (max 12.0 (/ (max bo tp le ri) 18.0))
        th (max 3.0 (/ (max bo tp le ri) 70.0)))

  ;; ------------------------------------------------ oval ends
  ;; The arcs are built from the resolved radii (sagitta off each end
  ;; chord), so dimensioning them reads back the radius that was typed.
  (if (= ptype "Oval")
      (progn
        (setq midl (pool:mid a d)
              ml (pool:unit (pool:perp (pool:v- d a))))
        (if (< (pool:dot (pool:v- midl cen) ml) 0.0)
            (setq ml (pool:v* ml -1.0)))
        (setq midr (pool:mid b c)
              mr (pool:unit (pool:perp (pool:v- c b))))
        (if (< (pool:dot (pool:v- midr cen) mr) 0.0)
            (setq mr (pool:v* mr -1.0)))
        (setq ores (pool:ovalends totl lrad rrad (distance midl midr)
                                  (distance a d) (distance b c))
              lrfit (car ores) rrfit (cadr ores)
              notes (append (nth 5 ores) notes)
              tipl (pool:v+ midl (pool:v* ml (caddr ores)))
              tipr (pool:v+ midr (pool:v* mr (cadddr ores))))
        (pool:arc3p a tipl d "POOL")
        (setq larc (entlast))
        (pool:arc3p b tipr c "POOL")
        (setq rarc (entlast))))

  ;; ------------------------------------------------ extents
  (setq allpts (append quad
                       (if tipl (list tipl tipr) nil))
        xmax (apply 'max (mapcar 'car allpts))
        ymax (apply 'max (mapcar 'cadr allpts))
        ymin (apply 'min (mapcar 'cadr allpts)))

  ;; ------------------------------------------------ dimensions
  (setvar "CLAYER" "DIMENSION")
  (if (= ptype "Rectangle")
      ;; per the reference: only the northern and western perimeter
      ;; dims, hooked to the wall endpoints (object-bounded) and
      ;; rotated along the side directions
      (progn
        (pool:dimrot (pool:cornerpoint quad corners 3 'next)   ; left wall top
                     (pool:cornerpoint quad corners 2 'prev)   ; right wall top
                     (angle d c)
                     (pool:outoff d c cen doff))
        (pool:dimrot (pool:cornerpoint quad corners 0 'next)   ; bottom wall left
                     (pool:cornerpoint quad corners 3 'prev)   ; top wall left
                     (angle a d)
                     (pool:outoff a d cen doff)))
      (if pool:*insq*
          ;; oval in-square, per the field sheet: T above the top side
          ;; and A outside the left arc -- the bottom side and right
          ;; chord repeat them, so they are not dimensioned (B joins
          ;; from the tip-to-tip dim below)
          (progn
            (pool:dimalg d c (pool:outoff d c cen doff))
            (pool:dimalg a d (list (- (car tipl) (* 1.2 doff))
                                   (cadr (pool:mid a d)))))
          (progn
            (setq endoff (* -0.6 doff))
            (pool:dimalg a b (pool:outoff a b cen doff))
            (pool:dimalg d c (pool:outoff d c cen doff))
            (pool:dimalg a d (pool:outoff a d cen endoff))
            (pool:dimalg b c (pool:outoff b c cen endoff)))))
  ;; corner annotations: one "Typ." at B when in-square, every corner
  ;; individually when out-of-square
  (if (= ptype "Rectangle")
      (pool:dimcorners quad corners arcs cen doff))
  ;; oval: radius dims read on the ARC from outside it (no line back to
  ;; the circle centre), plus the tip-to-tip overall
  (if (= ptype "Oval")
      (progn
        (pool:dimrad larc tipl ml doff)
        (pool:dimrad rarc tipr mr doff)
        ;; B tip-to-tip: on top per the field sheet when in-square,
        ;; below the pool (clear of the 4 side dims) out-of-square
        (pool:dimalg tipl tipr (list (car (pool:mid tipl tipr))
                                     (if pool:*insq*
                                         (+ ymax (* 1.9 doff))
                                         (- ymin (* 1.5 doff)))))))
  ;; provided cross dims, between their reference points, in the CROSS
  ;; DIMENSION style when the drawing has one
  (setq odim (pool:dimxbegin) k 0)
  (foreach m xmeas
    (if (nth 7 m)
        (progn
          (setq rpa (pool:cornerpoint quad corners (nth 3 m) (nth 4 m))
                rpb (pool:cornerpoint quad corners (nth 5 m) (nth 6 m)))
          (pool:dimalg rpa rpb
                       (pool:v+ (pool:mid rpa rpb)
                                (pool:v* (pool:unit (pool:perp (pool:v- rpb rpa)))
                                         (* (if (= 0 (rem k 2)) 0.2 -0.2) doff))))))
    (setq k (1+ k)))
  (pool:dimxend odim)
  (setvar "CLAYER" oldclay)

  ;; ------------------------------------------------ corner labels
  (foreach pr (list (list a "A") (list b "B") (list c "C") (list d "D"))
    (pool:text (pool:v+ (car pr)
                        (pool:v* (pool:unit (pool:v- (car pr) cen)) (* 1.5 th)))
               th (cadr pr) "POOL-NOTES"))

  ;; ------------------------------------------------ report table
  (setq rows (list (list "TOP SIDE (D-C)" tp (cadr meas))
                   (list "BOTTOM SIDE (A-B)" bo (car meas))
                   (list "LEFT END (A-D)" le (caddr meas))
                   (list "RIGHT END (B-C)" ri (cadddr meas))))
  ;; each cross measurement vs the actual distance between its
  ;; reference points in the fitted drawing
  (foreach m xmeas
    (setq rows (append rows
                       (list (list (nth 2 m) (nth 7 m)
                                   (distance (pool:cornerpoint quad corners (nth 3 m) (nth 4 m))
                                             (pool:cornerpoint quad corners (nth 5 m) (nth 6 m))))))))
  (if tri
      (setq rows (append rows
                         (list (list "TRI CHECK B-D" dbd
                                     (distance (cadr tri) (cadddr tri)))))))
  (if (= ptype "Oval")
      (setq rows (append rows
                         (list (list "TOTAL LENGTH" totl (distance tipl tipr))
                               (list "LEFT RADIUS" lrad lrfit)
                               (list "RIGHT RADIUS" rrad rrfit)))))
  ;; -------------------------------- pool bottom (interior pipeline)
  (cond
    ((= ptype "Rectangle")
     (setq rows (append rows (pool:hopper quad corners doff th))))
    ((= ptype "Oval")
     (setq rows (append rows (pool:hopovaldsp quad tipl tipr doff th)))))
  ;; corner treatments
  (if (and (= ptype "Rectangle") anycut)
      (if pool:*insq*
          (setq rows (append rows
                             (list (list (strcat "CORNERS " (car (car corners)))
                                         (cadr (car corners)) (cadr (car corners))))))
          (foreach lbl (list (list "A" 0) (list "B" 1) (list "C" 2) (list "D" 3))
            (if (/= (car (nth (cadr lbl) corners)) "Square")
                (setq rows (append rows
                                   (list (list (strcat "COR " (car lbl) " " (car (nth (cadr lbl) corners)))
                                               (cadr (nth (cadr lbl) corners))
                                               (cadr (nth (cadr lbl) corners))))))))))
  (if failed (setq notes (cons "CROSS DIMS FAILED" notes)))
  (setq notes (append notes pool:*valnotes*))
  (pool:report rows notes (+ xmax (* 2.0 doff)) ymax th "POOL-NOTES")
  (if failed
      (princ "\n*** CROSS DIMS FAILED -- sides held true, see report table ***")
      (princ "\nPool layout complete -- see the report table."))
  (princ))

;;; -------------------- round pools ------------------------------------
;;;
;;;  A round pool is a circle when it is in square and an ellipse when
;;;  the two overalls disagree -- B across, A up, both measured through
;;;  the middle.  There are no corners to best-fit, so the perimeter is
;;;  drawn exactly to the overalls and the report shows them as-drawn.
;;;
;;;  The interior is the True Oval hopper / sport bottom set, measured
;;;  off the pool's own extremes: H from the left edge, E to the right
;;;  edge, M/K off the top and bottom -- so H+G+F+E = B and M+L+K = A,
;;;  exactly like the field sheet.

;; Circle (a = b) or axis-aligned ellipse, on layer lay.
(defun pool:roundbody (cen b a lay)
  (if (< (abs (- a b)) 1.0e-6)
      (entmake (list '(0 . "CIRCLE")
                     (cons 8 lay)
                     (cons 10 (pool:wp cen))
                     (cons 40 (* 0.5 b))))
      (entmake (list '(0 . "ELLIPSE")
                     '(100 . "AcDbEntity")
                     (cons 8 lay)
                     '(100 . "AcDbEllipse")
                     (cons 10 (pool:wp cen))
                     (cons 11 (list (* 0.5 b) 0.0 0.0))   ; major axis, relative
                     (cons 210 '(0.0 0.0 1.0))
                     (cons 40 (/ a b))                    ; minor / major
                     (cons 41 0.0)
                     (cons 42 (* 2.0 pi))))))

;; Gray nominal round guide with its two overall ties.
(defun pool:roundpreview ( / cen pv)
  (setq cen (list 180.0 180.0))
  (pool:roundbody cen 360.0 360.0 "POOL-NOTES")
  (pool:pvadd (pool:setcol (entlast) pool:*pv-col*))
  (setq pv (list
    (pool:pvtie (list 0.0 415.0) (list 360.0 415.0) "B" 12.0)
    (pool:pvtie (list -55.0 0.0) (list -55.0 360.0) "A" 12.0)))
  pv)

;; Full guided flow for round pools.
(defun pool:roundflow ( / oldclay pv ans braw araw b a cen quad tipl tipr
                          doff th rows notes xmax ymax)
  (setq oldclay (getvar "CLAYER"))
  (setq pv (pool:roundpreview))
  (command "_.ZOOM" "_Window"
           (pool:wp (list -140.0 -80.0)) (pool:wp (list 500.0 470.0)))
  (princ "\nRound pool -- B across and A up, both through the middle.")
  (princ "\n(after the first answer, Back re-asks the previous one)")
  ;; in square, the two overalls are the same measurement
  (setq ans (pool:askseq
              (if pool:*insq*
                  (list (list 'b 'REQ "Overall diameter (A & B are equal)"
                              (append (cdr (assoc "B" pv)) (cdr (assoc "A" pv)))))
                  (list (list 'b 'REQ "B - overall length (across)"
                              (cdr (assoc "B" pv)))
                        (list 'a 'REQ "A - overall width (up)"
                              (cdr (assoc "A" pv))))))
        braw (pool:sq ans 'b)
        araw (if pool:*insq* braw (pool:sq ans 'a))
        b braw a araw)
  (pool:pvkill)

  (setq cen (list (* 0.5 b) (* 0.5 a))
        doff (max 12.0 (/ (max b a) 18.0))
        th (max 3.0 (/ (max b a) 70.0))
        notes nil
        pool:*dashlt* (pool:ltload "DASHED"))
  (pool:roundbody cen b a "POOL")
  (if (> (abs (- a b)) 1.0e-6)
      (princ "\nOut of square: the two overalls differ, so the pool is drawn as an ellipse.")
      (princ "\nIn square: A and B agree, so the pool is drawn as a true circle."))

  ;; the bounding box IS the hopper's frame: H/E off the left and right
  ;; extremes, M/K off the top and bottom
  (setq quad (list (list 0.0 0.0) (list b 0.0) (list b a) (list 0.0 a))
        tipl (list 0.0 (* 0.5 a))
        tipr (list b (* 0.5 a))
        xmax b ymax a)

  ;; per the field sheet: B across the top, A up the left side
  (setvar "CLAYER" "DIMENSION")
  (pool:dimalg tipl tipr (list (* 0.5 b) (+ a (* 1.4 doff))))
  (pool:dimalg (list (* 0.5 b) 0.0) (list (* 0.5 b) a)
               (list (- 0.0 (* 1.4 doff)) (* 0.5 a)))
  (setvar "CLAYER" oldclay)

  (setq rows (list (list "OV B" braw b) (list "OV A" araw a))
        rows (append rows (pool:hopovaldsp quad tipl tipr doff th)))
  (setq notes (append notes pool:*valnotes*))
  (pool:report rows notes (+ xmax (* 2.0 doff)) ymax th "POOL-NOTES")
  (princ "\nPool layout complete -- see the report table.")
  (princ))

;;; -------------------- roman pools ------------------------------------
;;;
;;;  Rectangle body of side length T and width A, with a radius end
;;;  behind corner drops at each side (per the Roman field sheet):
;;;  B/A overalls, S = tip setback past the side ends, S1 = corner
;;;  drop, V = end width between the arc springs, R1/R2 = end radii.
;;;  Letters close against the overalls like the grecian sheet
;;;  (S+T+S = B with T absorbing, S1+V+S1 = A with V absorbing).
;;;  Interior = the True Oval hopper / sport bottoms.

;; Per-end vertical resolution: returns (S1 V) against overall width.
(defun pool:romres (aov s1raw vraw)
  (cond
    (s1raw (list s1raw (- aov (* 2.0 s1raw))))
    (vraw (list (/ (- aov vraw) 2.0) vraw))
    (t (list (/ aov 6.0) (* aov (/ 2.0 3.0))))))

;; Build and draw one Roman end (per the reference drawing: straight
;; S1 stubs along the end line down to the arc springs, the arc
;; bulging S past the end line).  R is implied by S and V:
;; r = (S^2 + (V/2)^2) / 2S.  Returns (tip springT springB arcEname rImplied).
(defun pool:romend (pbot ptop m s v lay / u mide tip half st sb)
  (setq u (pool:unit (pool:v- ptop pbot))
        mide (pool:mid pbot ptop)
        tip (pool:v+ mide (pool:v* m s))
        half (* 0.5 v)
        st (pool:v+ mide (pool:v* u half))
        sb (pool:v- mide (pool:v* u half)))
  (if (> (distance ptop st) 1.0e-6) (pool:line ptop st lay))
  (if (> (distance pbot sb) 1.0e-6) (pool:line pbot sb lay))
  (pool:arc3p st tip sb lay)
  (list tip st sb (entlast)
        (/ (+ (* s s) (* half half)) (* 2.0 s))))

;; Gray nominal Roman guide, proportioned from the reference drawing:
;; full-length sides, vertical S1 stubs on the end lines, near-half-
;; round arcs, and the dashed tip-to-tip B centerline.
;; Cross-dim guide lines are NOT part of the preview: they are added by
;; pool:romancross once every side length is in, so the sheet stays
;; uncluttered while the perimeter is being measured.
(defun pool:romancross (pv)
  (append pv
          (list (cons "XAC" (list (pool:pvadd (pool:pvlined (list 0.0 0.0)
                                                            (list 360.0 300.0)))))
                (cons "XBD" (list (pool:pvadd (pool:pvlined (list 360.0 0.0)
                                                            (list 0.0 300.0))))))))

(defun pool:romanpreview ( / a b c d tl tr st1 sb1 st2 sb2 pv)
  (setq a (list 0.0 0.0) b (list 360.0 0.0)
        c (list 360.0 300.0) d (list 0.0 300.0)
        tl (list -52.0 150.0) tr (list 412.0 150.0)
        st1 (list 0.0 240.0) sb1 (list 0.0 60.0)
        st2 (list 360.0 240.0) sb2 (list 360.0 60.0))
  (pool:pvadd (pool:pvline a b))
  (pool:pvadd (pool:pvline d c))
  (pool:pvadd (pool:pvline d st1))
  (pool:pvadd (pool:pvline a sb1))
  (pool:pvadd (pool:pvline c st2))
  (pool:pvadd (pool:pvline b sb2))
  (pool:arc3p st1 tl sb1 "POOL-NOTES")
  (pool:pvadd (pool:setcol (entlast) pool:*pv-col*))
  (pool:arc3p st2 tr sb2 "POOL-NOTES")
  (pool:pvadd (pool:setcol (entlast) pool:*pv-col*))
  (setq pv (list
    (pool:pvtie tl tr "B" 10.0)          ; the tip-to-tip centerline tape
    (pool:pvtie (list 0.0 330.0) (list 360.0 330.0) "T" 10.0)
    (pool:pvtie (list -52.0 330.0) (list 0.0 330.0) "SL" 10.0)
    (pool:pvtie (list 360.0 330.0) (list 412.0 330.0) "SR" 10.0)
    (pool:pvtie (list -95.0 0.0) (list -95.0 300.0) "A" 10.0)
    (pool:pvtie (list -72.0 240.0) (list -72.0 300.0) "S1L" 10.0)
    (pool:pvtie (list -72.0 60.0) (list -72.0 240.0) "VL" 10.0)
    (pool:pvtie (list 432.0 240.0) (list 432.0 300.0) "S1R" 10.0)
    (pool:pvtie (list 432.0 60.0) (list 432.0 240.0) "VR" 10.0)
    (pool:pvtie tl (list 40.0 210.0) "R1" 10.0)
    (pool:pvtie tr (list 320.0 210.0) "R2" 10.0)))
  pv)

;; Full guided flow for Roman pools.
(defun pool:romanflow ( / oldclay perfect pv braw araw traw rombad ans
                          slraw srraw s1lraw s1rraw vlraw vrraw r1 r2
                          hres sl tv sr lres rres s1l vl s1r vr
                          dac dbd fq quad failed a b c d cen meas notes
                          ml mr lend rend tipl tipr doff th odim pr
                          allpts xmax ymax ymin rows xcol xa)
  (setq oldclay (getvar "CLAYER"))
  (defun rm:perfect ( / v)
    (if pool:*insq*
        (progn (setq perfect t) nil)
        (progn (setq perfect (pool:askyn "Are both ends perfect (identical)"
                                         nil nil))
               nil)))
  (defun rm:guide ()
    (pool:pvkill)
    (setq pv (pool:romanpreview))
    (command "_.ZOOM" "_Window"
             (pool:wp (list -130.0 -80.0)) (pool:wp (list 470.0 380.0)))
    (princ "\nRoman sheet -- the RED tie is the dimension being asked for.")
    (princ "\n(Back re-asks the previous question)")
    nil)
  (defun rm:letters ( / ans)
  (setq ans (pool:askseqb
              (append
                (list (list 'b 'REQ "B - overall length" (cdr (assoc "B" pv)))
                      (list 'a 'REQ "A - overall width" (cdr (assoc "A" pv)))
                      (list 'tt 'NAX "T - side length (top & bottom)"
                            (cdr (assoc "T" pv))))
                (if perfect
                    (list (list 'sl 'NAX "S - end setback (both ends)"
                                (append (cdr (assoc "SL" pv)) (cdr (assoc "SR" pv))))
                          (list 's1l 'NAX "S1 - corner drop (all corners)"
                                (append (cdr (assoc "S1L" pv)) (cdr (assoc "S1R" pv))))
                          (list 'vl 'NAX "V - end width (both ends)"
                                (append (cdr (assoc "VL" pv)) (cdr (assoc "VR" pv))))
                          (list 'r1 'NAX "R - end radius (both ends, check)"
                                (append (cdr (assoc "R1" pv)) (cdr (assoc "R2" pv)))))
                    (list (list 'sl 'NAX "S - LEFT end setback" (cdr (assoc "SL" pv)))
                          (list 'sr 'NAX "S - RIGHT end setback" (cdr (assoc "SR" pv)))
                          (list 's1l 'NAX "S1 - LEFT corner drop" (cdr (assoc "S1L" pv)))
                          (list 's1r 'NAX "S1 - RIGHT corner drop" (cdr (assoc "S1R" pv)))
                          (list 'vl 'NAX "V - LEFT end width" (cdr (assoc "VL" pv)))
                          (list 'vr 'NAX "V - RIGHT end width" (cdr (assoc "VR" pv)))
                          (list 'r1 'NAX "R1 - LEFT end radius (check)" (cdr (assoc "R1" pv)))
                          (list 'r2 'NAX "R2 - RIGHT end radius (check)"
                                (cdr (assoc "R2" pv))))))
              t))
  (if (eq ans 'POOL-BACK)
      'POOL-BACK
      (progn
  (setq braw (pool:sq ans 'b) araw (pool:sq ans 'a) traw (pool:sq ans 'tt)
        slraw (pool:sq ans 'sl) s1lraw (pool:sq ans 's1l)
        vlraw (pool:sq ans 'vl) r1 (pool:sq ans 'r1)
        srraw (if perfect slraw (pool:sq ans 'sr))
        s1rraw (if perfect s1lraw (pool:sq ans 's1r))
        vrraw (if perfect vlraw (pool:sq ans 'vr))
        r2 (if perfect r1 (pool:sq ans 'r2)))
      nil)))

  ;; every side length is in -- now the cross dims appear on the guide
  (defun rm:cross ( / ans xg)
    (if pool:*insq*
        nil
        (progn
          (setq pv (pool:romancross pv)
                xg (append (cdr (assoc "XAC" pv)) (cdr (assoc "XBD" pv)))
                ans (pool:askseqb
                      (list (list 'ac 'NAX "Cross dim body A-C" (cdr (assoc "XAC" pv)))
                            (list 'bd 'NAX "Cross dim body B-D" (cdr (assoc "XBD" pv))))
                      t))
          (if (eq ans 'POOL-BACK)
              (progn (pool:pvdel xg) 'POOL-BACK)
              (progn (setq dac (pool:sq ans 'ac)
                           dbd (pool:sq ans 'bd))
                     nil)))))

  (pool:stages (list 'rm:perfect 'rm:guide 'rm:letters 'rm:cross))
  (pool:pvkill)

  ;; resolve: per end S1/V vs A (V absorbs); then S + T + S = B with
  ;; T absorbing -- an NA S can come from the chain, or from the end
  ;; radius (arc sagitta: S = R - sqrt(R^2 - (V/2)^2))
  (setq lres (pool:romres araw s1lraw vlraw)
        s1l (car lres) vl (cadr lres)
        rres (pool:romres araw s1rraw vrraw)
        s1r (car rres) vr (cadr rres)
        sl (cond
             (slraw slraw)
             (traw (/ (- braw traw) 2.0))
             ((and r1 (>= r1 (* 0.5 vl)))
              (- r1 (sqrt (max 0.0 (- (* r1 r1) (* 0.25 vl vl))))))
             (t (/ braw 8.0)))
        sr (cond
             (srraw srraw)
             (traw (/ (- braw traw) 2.0))
             ((and r2 (>= r2 (* 0.5 vr)))
              (- r2 (sqrt (max 0.0 (- (* r2 r2) (* 0.25 vr vr))))))
             (t (/ braw 8.0)))
        tv (- braw sl sr))

  ;; every letter must close POSITIVE against the overalls -- warned
  ;; NOW, before the pool is drawn or the bottom letters asked, and
  ;; red in the report after
  (if (<= s1l 1.0e-6)
      (progn (setq s1l (min 12.0 (* 0.125 araw)) vl (- araw s1l s1l) rombad t)
             (pool:valnote "ROMAN S1 LEFT NOT POSITIVE - ADJUSTED")))
  (if (<= s1r 1.0e-6)
      (progn (setq s1r (min 12.0 (* 0.125 araw)) vr (- araw s1r s1r) rombad t)
             (pool:valnote "ROMAN S1 RIGHT NOT POSITIVE - ADJUSTED")))
  (if (<= vl 1.0e-6)
      (progn (setq vl (min 12.0 (* 0.5 araw)) s1l (/ (- araw vl) 2.0) rombad t)
             (pool:valnote "ROMAN S1 + V + S1 LEFT DOES NOT FIT A - ADJUSTED")))
  (if (<= vr 1.0e-6)
      (progn (setq vr (min 12.0 (* 0.5 araw)) s1r (/ (- araw vr) 2.0) rombad t)
             (pool:valnote "ROMAN S1 + V + S1 RIGHT DOES NOT FIT A - ADJUSTED")))
  (if (<= sl 1.0e-6)
      (progn (setq sl (min 12.0 (/ braw 8.0)) rombad t)
             (pool:valnote "ROMAN S LEFT NOT POSITIVE - ADJUSTED")))
  (if (<= sr 1.0e-6)
      (progn (setq sr (min 12.0 (/ braw 8.0)) rombad t)
             (pool:valnote "ROMAN S RIGHT NOT POSITIVE - ADJUSTED")))
  (if (<= (setq tv (- braw sl sr)) 1.0e-6)
      (progn
        (setq tv (min 12.0 (* 0.25 braw))
              sl (/ (- braw tv) 2.0) sr sl rombad t)
        (pool:valnote "ROMAN S + T + S DOES NOT FIT B - ADJUSTED")))

  ;; body fit (sides T, ends A) + roman ends
  (princ "\nFitting pool body to the measurements ...")
  (setq fq (pool:fitquad tv tv araw araw dac dbd pool:*side-tol* pool:*cross-tol*)
        quad (car fq) failed (cadr fq)
        a (car quad) b (cadr quad) c (caddr quad) d (cadddr quad)
        cen (pool:v* (pool:v+ (pool:v+ a b) (pool:v+ c d)) 0.25)
        meas (pool:quadmeas quad)
        notes nil
        doff (max 12.0 (/ (max tv araw) 18.0))
        th (max 3.0 (/ (max tv araw) 70.0))
        pool:*dashlt* (pool:ltload "DASHED"))
  (pool:line a b "POOL")
  (pool:line c d "POOL")
  (pool:lined b c)
  (pool:lined d a)
  (setq ml (pool:unit (pool:perp (pool:v- d a))))
  (if (< (pool:dot (pool:v- (pool:mid a d) cen) ml) 0.0)
      (setq ml (pool:v* ml -1.0)))
  (setq mr (pool:unit (pool:perp (pool:v- c b))))
  (if (< (pool:dot (pool:v- (pool:mid b c) cen) mr) 0.0)
      (setq mr (pool:v* mr -1.0)))
  (setq lend (pool:romend a d ml sl vl "POOL")
        rend (pool:romend b c mr sr vr "POOL")
        tipl (car lend) tipr (car rend))

  ;; dims
  (setq allpts (append quad (list tipl tipr (cadr lend) (caddr lend)
                                  (cadr rend) (caddr rend)))
        xmax (apply 'max (mapcar 'car allpts))
        ymax (apply 'max (mapcar 'cadr allpts))
        ymin (apply 'min (mapcar 'cadr allpts)))
  (setvar "CLAYER" "DIMENSION")
  (if pool:*insq*
      ;; in-square, per the field sheet: S+T+S share a row along the
      ;; top with B outboard of them (S shows at BOTH ends), and
      ;; S1+V+S1 share a column beside the left end with A outboard
      ;; (S1 shows at BOTH corners); the bottom side repeats T and is
      ;; not dimensioned
      (progn
        (setq xcol (- (car tipl) (* 0.9 doff))
              xa (- (car tipl) (* 1.9 doff)))
        ;; row 1: S (left tip to side start), T, S (side end to right tip)
        (pool:dimalg (list (car tipl) ymax) d
                     (list (* 0.5 (+ (car tipl) (car d))) (+ ymax doff)))
        (pool:dimalg d c (list (car (pool:mid d c)) (+ ymax doff)))
        (pool:dimalg c (list (car tipr) ymax)
                     (list (* 0.5 (+ (car c) (car tipr))) (+ ymax doff)))
        ;; row 2: B, tip to tip
        (pool:dimalg tipl tipr (list (car (pool:mid tipl tipr))
                                     (+ ymax (* 1.9 doff))))
        ;; column 1: S1, V, S1 down the left end line
        (pool:dimalg d (cadr lend)
                     (list xcol (* 0.5 (+ (cadr d) (cadr (cadr lend))))))
        (pool:dimalg (cadr lend) (caddr lend)
                     (list xcol (cadr (pool:mid (cadr lend) (caddr lend)))))
        (pool:dimalg (caddr lend) a
                     (list xcol (* 0.5 (+ (cadr (caddr lend)) (cadr a)))))
        ;; column 2: A, the overall width
        (pool:dimalg a d (list xa (cadr (pool:mid a d)))))
      (progn
        (pool:dimalg a b (pool:outoff a b cen doff))
        (pool:dimalg d c (pool:outoff d c cen doff))
        (pool:dimalg tipl tipr (list (car (pool:mid tipl tipr))
                                     (- ymin (* 1.5 doff))))
        (pool:dimalg a d (list (- (car tipl) (* 1.2 doff))
                               (cadr (pool:mid a d))))))
  (pool:dimrad (nth 3 lend) tipl ml doff)
  (pool:dimrad (nth 3 rend) tipr mr doff)
  (setq odim (pool:dimxbegin))
  (if dac
      (pool:dimalg a c (pool:v+ (pool:mid a c)
                                (pool:v* (pool:unit (pool:perp (pool:v- c a)))
                                         (* 0.2 doff)))))
  (if dbd
      (pool:dimalg b d (pool:v+ (pool:mid b d)
                                (pool:v* (pool:unit (pool:perp (pool:v- d b)))
                                         (* -0.2 doff)))))
  (pool:dimxend odim)
  (setvar "CLAYER" oldclay)

  ;; body corner labels
  (foreach pr (list (list a "A") (list b "B") (list c "C") (list d "D"))
    (pool:text (pool:v+ (car pr)
                        (pool:v* (pool:unit (pool:v- (car pr) cen)) (* 1.5 th)))
               th (cadr pr) "POOL-NOTES"))

  ;; report
  (setq rows (list
    (list "OV B" braw (distance tipl tipr))
    (list "OV A" araw (distance a d))
    (append (list "T TOP" traw (distance d c)) (if rombad (list t) nil))
    (append (list "T BOT" traw (distance a b)) (if rombad (list t) nil))
    (append (list "S LEFT" slraw (distance tipl (pool:mid a d)))
            (if rombad (list t) nil))
    (append (list "S RIGHT" srraw (distance tipr (pool:mid b c)))
            (if rombad (list t) nil))
    (append (list "S1 LEFT" s1lraw (/ (- (distance a d)
                                         (distance (cadr lend) (caddr lend))) 2.0))
            (if rombad (list t) nil))
    (append (list "S1 RIGHT" s1rraw (/ (- (distance b c)
                                          (distance (cadr rend) (caddr rend))) 2.0))
            (if rombad (list t) nil))
    (append (list "V LEFT" vlraw (distance (cadr lend) (caddr lend)))
            (if rombad (list t) nil))
    (append (list "V RIGHT" vrraw (distance (cadr rend) (caddr rend)))
            (if rombad (list t) nil))
    (list "R1" r1 (nth 4 lend))
    (list "R2" r2 (nth 4 rend))))
  (if (not pool:*insq*)
      (setq rows (append rows
                         (list (list "CROSS A-C" dac (nth 4 meas))
                               (list "CROSS B-D" dbd (nth 5 meas))))))
  ;; interior: the True Oval hopper / sport bottoms
  (setq rows (append rows (pool:hopovaldsp quad tipl tipr doff th)))
  (if failed (setq notes (cons "CROSS DIMS FAILED" notes)))
  (setq notes (append notes pool:*valnotes*))
  (pool:report rows notes (+ xmax (* 2.0 doff)) ymax th "POOL-NOTES")
  (if failed
      (princ "\n*** CROSS DIMS FAILED -- sides held true, see report table ***")
      (princ "\nPool layout complete -- see the report table."))
  (princ))

;;; -------------------- mutt pools -------------------------------------
;;;
;;;  A "mutt" is a rectangle body whose DEEP end (left) and SHALLOW
;;;  end (right) are picked independently -- a roman deep end with a
;;;  grecian shallow end, a grecian deep end with an oval shallow end,
;;;  and so on.  End styles:
;;;    Square  -- plain wall (the rectangle end)
;;;    Grecian -- corner cuts: S setback / S1 drop / S2 face (check)
;;;    ROman   -- S1 stubs + arc bulging S past the end line (V, R)
;;;    Oval    -- full-width arc (R, NA = half round)
;;;  B is the tip-to-tip overall, A the overall width; each end's
;;;  letters close against them exactly like their home sheets, and
;;;  the body length is what's left of B after the end bulges.
;;;  Interior = the standard rectangle bottom pipeline, anchored tip
;;;  to tip (no corner ties -- the ends are too varied to tie to).

;; Resolve one mutt end.  Returns (ext inset s1 v r bad):
;; ext = how far the end sticks out past the body end line, inset =
;; how far a grecian cut eats into the sides.  Emits valnotes on the
;; way out of anything that doesn't close.
(defun pool:muttres (style sraw s1raw vraw rraw aov bov nm / s s1 v ext
                                                            bad half res)
  (cond
    ((= style "Grecian")
     (setq s (if sraw sraw (/ bov 8.0))
           s1 (if s1raw s1raw (/ aov 6.0))
           v (- aov s1 s1))
     (if (<= v 1.0e-6)
         (progn
           (setq s1 (min 12.0 (* 0.125 aov)) v (- aov s1 s1) bad t)
           (pool:valnote (strcat nm " END S1 + V + S1 DOES NOT FIT A - ADJUSTED"))))
     (if (<= s 1.0e-6)
         (progn
           (setq s (min 12.0 (/ bov 8.0)) bad t)
           (pool:valnote (strcat nm " END S NOT POSITIVE - ADJUSTED"))))
     (list 0.0 s s1 v nil bad))
    ((= style "ROman")
     (setq res (pool:romres aov s1raw vraw)
           s1 (car res) v (cadr res))
     (if (<= v 1.0e-6)
         (progn
           (setq s1 (min 12.0 (* 0.125 aov)) v (- aov s1 s1) bad t)
           (pool:valnote (strcat nm " END S1 + V + S1 DOES NOT FIT A - ADJUSTED"))))
     (setq s (cond
               (sraw sraw)
               ((and rraw (>= rraw (* 0.5 v)))
                (- rraw (sqrt (max 0.0 (- (* rraw rraw) (* 0.25 v v))))))
               (t (/ bov 8.0))))
     (if (<= s 1.0e-6)
         (progn
           (setq s (min 12.0 (/ bov 8.0)) bad t)
           (pool:valnote (strcat nm " END S NOT POSITIVE - ADJUSTED"))))
     (list s 0.0 s1 v rraw bad))
    ((= style "Oval")
     (setq half (* 0.5 aov)
           ext (cond
                 ((and rraw (>= rraw half))
                  (- rraw (sqrt (max 0.0 (- (* rraw rraw) (* half half))))))
                 (rraw
                  (pool:valnote (strcat nm " END RADIUS SMALLER THAN A/2 - HALF ROUND DRAWN"))
                  (setq bad t)
                  half)
                 (t half)))
     (list ext 0.0 nil nil rraw bad))
    (t (list 0.0 0.0 nil nil nil nil))))

;; Draw one mutt end onto the fitted body.  pbot/ptop = the body
;; corners on this end line, pb2/pt2 = where the sides start (inset
;; for a grecian end), m = outward unit normal.
;; Returns (tip springT springB arcent rfit) -- tip is the extreme
;; point B is taped to; springs are the wall/stub ends (the body
;; corners themselves on a square or oval end).
(defun pool:muttend (pbot ptop pb2 pt2 m style s1 v ext lay / uu wb wt tip o)
  (setq uu (pool:unit (pool:v- ptop pbot)))
  (cond
    ((= style "Square")
     (pool:line pbot ptop lay)
     (list (pool:mid pbot ptop) ptop pbot nil nil))
    ((= style "Grecian")
     (setq wb (pool:v+ pbot (pool:v* uu s1))
           wt (pool:v- ptop (pool:v* uu s1)))
     (pool:line pb2 wb lay)
     (pool:line wb wt lay)
     (pool:line wt pt2 lay)
     (list (pool:mid pbot ptop) wt wb nil nil))
    ((= style "ROman")
     (pool:romend pbot ptop m ext v lay))
    (t                                  ; Oval
     (setq tip (pool:v+ (pool:mid pbot ptop) (pool:v* m ext)))
     (pool:arc3p ptop tip pbot lay)
     (setq o (pool:circum ptop tip pbot))
     (list tip ptop pbot (entlast) (if o (distance o tip) ext)))))

;; Nominal preview of one mutt end on the 360x300 guide body.
;; wx = the body end line, sgn = -1 left / +1 right, sfx = "L"/"R".
;; Returns (tip inset ties).
(defun pool:muttpvend (wx sgn style sfx / a d tip ins ties tx)
  (setq a (list wx 0.0) d (list wx 300.0)
        tip (list wx 150.0) ins 0.0 ties nil)
  (cond
    ((= style "Square")
     (pool:pvadd (pool:pvline a d)))
    ((= style "Grecian")
     (setq ins 60.0)
     (pool:pvadd (pool:pvline (list (+ wx (* sgn 60.0)) 0.0) (list wx 60.0)))
     (pool:pvadd (pool:pvline (list wx 60.0) (list wx 240.0)))
     (pool:pvadd (pool:pvline (list wx 240.0) (list (+ wx (* sgn 60.0)) 300.0)))
     (setq ties (list (pool:pvtie (list (+ wx (* sgn 60.0)) 0.0) (list wx 60.0)
                                  (strcat "S2" sfx) 10.0))))
    ((= style "ROman")
     (setq tip (list (+ wx (* sgn 52.0)) 150.0))
     (pool:pvadd (pool:pvline d (list wx 240.0)))
     (pool:pvadd (pool:pvline a (list wx 60.0)))
     (pool:arc3p (list wx 240.0) tip (list wx 60.0) "POOL-NOTES")
     (pool:pvadd (pool:setcol (entlast) pool:*pv-col*))
     (setq ties (list (pool:pvtie tip (list (+ wx (* sgn -40.0)) 210.0)
                                  (strcat "R" sfx) 10.0))))
    (t                                  ; Oval
     (setq tip (list (+ wx (* sgn 90.0)) 150.0))
     (pool:arc3p d tip a "POOL-NOTES")
     (pool:pvadd (pool:setcol (entlast) pool:*pv-col*))
     (setq ties (list (pool:pvtie tip (list (+ wx (* sgn -40.0)) 210.0)
                                  (strcat "R" sfx) 10.0)))))
  ;; grecian and roman ends share the S / S1 / V letters
  (if (or (= style "Grecian") (= style "ROman"))
      (setq tx (+ wx (* sgn 72.0))
            ties (append ties
                   (list (pool:pvtie (list (car tip) 330.0)
                                     (list (+ wx (* sgn ins)) 330.0)
                                     (strcat "S" sfx) 10.0)
                         (pool:pvtie (list tx 240.0) (list tx 300.0)
                                     (strcat "S1" sfx) 10.0)
                         (pool:pvtie (list tx 60.0) (list tx 240.0)
                                     (strcat "V" sfx) 10.0)))))
  (list tip ins ties))

;; Gray nominal mutt guide: 360x300 body, each end drawn in its chosen
;; style, the dashed tip-to-tip B centerline and the A tape.
(defun pool:muttpreview (dst sst / le re)
  (setq le (pool:muttpvend 0.0 -1.0 dst "L")
        re (pool:muttpvend 360.0 1.0 sst "R"))
  (pool:pvadd (pool:pvline (list (cadr le) 0.0) (list (- 360.0 (cadr re)) 0.0)))
  (pool:pvadd (pool:pvline (list (cadr le) 300.0) (list (- 360.0 (cadr re)) 300.0)))
  (append
    (list (pool:pvtie (car le) (car re) "B" 10.0)
          (pool:pvtie (list -125.0 0.0) (list -125.0 300.0) "A" 10.0))
    (caddr le) (caddr re)))

;; Full guided flow for mutt pools.
(defun pool:muttflow ( / oldclay pv dstyle sstyle ans braw araw
                         dsraw ds1raw dvraw ds2raw drraw
                         ssraw ss1raw svraw ss2raw srraw
                         dres sres extl extr insl insr tv muttbad
                         dac dbd fq quad failed a b c d cen meas notes
                         uab udc ml mr lend rend tipl tipr
                         pab0 pab1 pdc0 pdc1 doff th odim
                         allpts xmax ymax ymin rows xcol xa)
  (setq oldclay (getvar "CLAYER"))

  (defun mu:ends ( / v)
    (setq v (pool:askkw "DEEP end (left) style"
                        "Square Grecian ROman Oval"
                        "Square/Grecian/ROman/Oval" nil t))
    (if (eq v 'POOL-BACK)
        v
        (progn
          (setq dstyle v
                v (pool:askkw "SHALLOW end (right) style"
                              "Square Grecian ROman Oval"
                              "Square/Grecian/ROman/Oval" nil t))
          (if (eq v 'POOL-BACK)
              v
              (progn (setq sstyle v) nil)))))

  (defun mu:guide ()
    (pool:pvkill)
    (setq pv (pool:muttpreview dstyle sstyle))
    (command "_.ZOOM" "_Window"
             (pool:wp (list -160.0 -80.0)) (pool:wp (list 520.0 380.0)))
    (princ "\nMutt sheet -- deep end LEFT, shallow end RIGHT; the RED tie is the dimension being asked for.")
    (princ "\n(Back re-asks the previous question)")
    nil)

  ;; the letter items one end contributes, per its style
  (defun mu:enditems (style sfx nm ks ks1 kv ks2 kr)
    (cond
      ((= style "Grecian")
       (list (list ks 'NAX (strcat nm " end S - corner setback")
                   (cdr (assoc (strcat "S" sfx) pv)))
             (list ks1 'NAX (strcat nm " end S1 - corner drop")
                   (cdr (assoc (strcat "S1" sfx) pv)))
             (list ks2 'NAX (strcat nm " end S2 - corner face (check)")
                   (cdr (assoc (strcat "S2" sfx) pv)))))
      ((= style "ROman")
       (list (list ks 'NAX (strcat nm " end S - tip setback")
                   (cdr (assoc (strcat "S" sfx) pv)))
             (list ks1 'NAX (strcat nm " end S1 - corner drop")
                   (cdr (assoc (strcat "S1" sfx) pv)))
             (list kv 'NAX (strcat nm " end V - width between springs")
                   (cdr (assoc (strcat "V" sfx) pv)))
             (list kr 'NAX (strcat nm " end R - radius (check)")
                   (cdr (assoc (strcat "R" sfx) pv)))))
      ((= style "Oval")
       (list (list kr 'NAX (strcat nm " end R - radius (NA = half round)")
                   (cdr (assoc (strcat "R" sfx) pv)))))
      (t nil)))

  (defun mu:letters ( / ans)
    (setq ans (pool:askseqb
                (append
                  (list (list 'b 'REQ "B - overall length (tip to tip)"
                              (cdr (assoc "B" pv)))
                        (list 'a 'REQ "A - overall width"
                              (cdr (assoc "A" pv))))
                  (mu:enditems dstyle "L" "Deep" 'dsl 'ds1 'dv 'ds2 'dr)
                  (mu:enditems sstyle "R" "Shallow" 'ssl 'ss1 'sv 'ss2 'sr))
                t))
    (if (eq ans 'POOL-BACK)
        'POOL-BACK
        (progn
          (setq braw (pool:sq ans 'b) araw (pool:sq ans 'a)
                dsraw (pool:sq ans 'dsl) ds1raw (pool:sq ans 'ds1)
                dvraw (pool:sq ans 'dv) ds2raw (pool:sq ans 'ds2)
                drraw (pool:sq ans 'dr)
                ssraw (pool:sq ans 'ssl) ss1raw (pool:sq ans 'ss1)
                svraw (pool:sq ans 'sv) ss2raw (pool:sq ans 'ss2)
                srraw (pool:sq ans 'sr))
          nil)))

  ;; body cross dims, out-of-square only (the ends ride on the body)
  (defun mu:cross ( / ans xg)
    (if pool:*insq*
        nil
        (progn
          (setq pv (pool:romancross pv)
                xg (append (cdr (assoc "XAC" pv)) (cdr (assoc "XBD" pv)))
                ans (pool:askseqb
                      (list (list 'ac 'NAX "Cross dim body A-C"
                                  (cdr (assoc "XAC" pv)))
                            (list 'bd 'NAX "Cross dim body B-D"
                                  (cdr (assoc "XBD" pv))))
                      t))
          (if (eq ans 'POOL-BACK)
              (progn (pool:pvdel xg) 'POOL-BACK)
              (progn (setq dac (pool:sq ans 'ac)
                           dbd (pool:sq ans 'bd))
                     nil)))))

  (pool:stages (list 'mu:ends 'mu:guide 'mu:letters 'mu:cross))
  (pool:pvkill)

  ;; -------- resolve the ends, then the body against B
  (setq dres (pool:muttres dstyle dsraw ds1raw dvraw drraw araw braw "DEEP")
        sres (pool:muttres sstyle ssraw ss1raw svraw srraw araw braw "SHALLOW")
        extl (car dres) insl (cadr dres)
        extr (car sres) insr (cadr sres)
        muttbad (or (nth 5 dres) (nth 5 sres))
        tv (- braw extl extr))
  (if (<= (- tv insl insr) 1.0e-6)
      (progn
        (setq tv (+ insl insr (min 12.0 (* 0.25 braw))) muttbad t)
        (pool:valnote "MUTT ENDS DO NOT FIT B - BODY ADJUSTED")))

  ;; -------- fit the body, draw sides and ends
  (princ "\nFitting pool body to the measurements ...")
  (setq fq (pool:fitquad tv tv araw araw dac dbd pool:*side-tol* pool:*cross-tol*)
        quad (car fq) failed (cadr fq)
        a (car quad) b (cadr quad) c (caddr quad) d (cadddr quad)
        cen (pool:v* (pool:v+ (pool:v+ a b) (pool:v+ c d)) 0.25)
        meas (pool:quadmeas quad)
        notes nil
        doff (max 12.0 (/ (max braw araw) 18.0))
        th (max 3.0 (/ (max braw araw) 70.0))
        pool:*dashlt* (pool:ltload "DASHED")
        uab (pool:unit (pool:v- b a))
        udc (pool:unit (pool:v- c d)))
  (setq ml (pool:unit (pool:perp (pool:v- d a))))
  (if (< (pool:dot (pool:v- (pool:mid a d) cen) ml) 0.0)
      (setq ml (pool:v* ml -1.0)))
  (setq mr (pool:unit (pool:perp (pool:v- c b))))
  (if (< (pool:dot (pool:v- (pool:mid b c) cen) mr) 0.0)
      (setq mr (pool:v* mr -1.0)))
  (setq pab0 (pool:v+ a (pool:v* uab insl))
        pab1 (pool:v- b (pool:v* uab insr))
        pdc0 (pool:v+ d (pool:v* udc insl))
        pdc1 (pool:v- c (pool:v* udc insr)))
  (pool:line pab0 pab1 "POOL")
  (pool:line pdc0 pdc1 "POOL")
  (setq lend (pool:muttend a d pab0 pdc0 ml dstyle
                           (caddr dres) (nth 3 dres) extl "POOL")
        rend (pool:muttend b c pab1 pdc1 mr sstyle
                           (caddr sres) (nth 3 sres) extr "POOL")
        tipl (car lend) tipr (car rend))

  ;; -------- extents / dims
  (setq allpts (append quad (list tipl tipr (cadr lend) (caddr lend)
                                  (cadr rend) (caddr rend)))
        xmax (apply 'max (mapcar 'car allpts))
        ymax (apply 'max (mapcar 'cadr allpts))
        ymin (apply 'min (mapcar 'cadr allpts)))
  (setvar "CLAYER" "DIMENSION")
  (if pool:*insq*
      ;; field-sheet set: each end's letters where its home sheet puts
      ;; them -- S row + top side under B along the top, S1/V columns
      ;; beside their ends, A outboard left, S2 on grecian cuts, R on
      ;; the arcs (below)
      (progn
        (if (or (= dstyle "Grecian") (= dstyle "ROman"))
            (pool:dimalg (list (car tipl) ymax) pdc0
                         (list (* 0.5 (+ (car tipl) (car pdc0)))
                               (+ ymax doff))))
        (pool:dimalg pdc0 pdc1
                     (list (car (pool:mid pdc0 pdc1)) (+ ymax doff)))
        (if (or (= sstyle "Grecian") (= sstyle "ROman"))
            (pool:dimalg pdc1 (list (car tipr) ymax)
                         (list (* 0.5 (+ (car pdc1) (car tipr)))
                               (+ ymax doff))))
        (pool:dimalg tipl tipr (list (car (pool:mid tipl tipr))
                                     (+ ymax (* 1.9 doff))))
        (setq xcol (- (car tipl) (* 0.9 doff))
              xa (- (car tipl) (* 1.9 doff)))
        (if (or (= dstyle "Grecian") (= dstyle "ROman"))
            (progn
              (pool:dimalg d (cadr lend)
                           (list xcol (* 0.5 (+ (cadr d) (cadr (cadr lend))))))
              (pool:dimalg (cadr lend) (caddr lend)
                           (list xcol (cadr (pool:mid (cadr lend) (caddr lend)))))))
        (if (or (= sstyle "Grecian") (= sstyle "ROman"))
            (progn
              (pool:dimalg c (cadr rend)
                           (list (+ (car tipr) (* 0.9 doff))
                                 (* 0.5 (+ (cadr c) (cadr (cadr rend))))))
              (pool:dimalg (cadr rend) (caddr rend)
                           (list (+ (car tipr) (* 0.9 doff))
                                 (cadr (pool:mid (cadr rend) (caddr rend)))))))
        (pool:dimalg a d (list xa (cadr (pool:mid a d))))
        (if (= dstyle "Grecian")
            (pool:dimalg pab0 (caddr lend)
                         (pool:outoffp pab0 (caddr lend)
                                       (list pab0 pab1 pdc1 pdc0) doff)))
        (if (= sstyle "Grecian")
            (pool:dimalg pab1 (caddr rend)
                         (pool:outoffp pab1 (caddr rend)
                                       (list pab0 pab1 pdc1 pdc0) doff))))
      ;; out-of-square: the simple roman-style set + dashed crosses
      (progn
        (pool:dimalg pab0 pab1 (pool:outoff pab0 pab1 cen doff))
        (pool:dimalg pdc0 pdc1 (pool:outoff pdc0 pdc1 cen doff))
        (pool:dimalg tipl tipr (list (car (pool:mid tipl tipr))
                                     (- ymin (* 1.5 doff))))
        (pool:dimalg a d (list (- (car tipl) (* 1.2 doff))
                               (cadr (pool:mid a d))))))
  (pool:dimrad (nth 3 lend) tipl ml doff)
  (pool:dimrad (nth 3 rend) tipr mr doff)
  (if (not pool:*insq*)
      (progn
        (setq odim (pool:dimxbegin))
        (if dac
            (pool:dimalg a c (pool:v+ (pool:mid a c)
                                      (pool:v* (pool:unit (pool:perp (pool:v- c a)))
                                               (* 0.2 doff)))))
        (if dbd
            (pool:dimalg b d (pool:v+ (pool:mid b d)
                                      (pool:v* (pool:unit (pool:perp (pool:v- d b)))
                                               (* -0.2 doff)))))
        (pool:dimxend odim)))
  (setvar "CLAYER" oldclay)

  ;; -------- body corner labels
  (foreach fq (list (list a "A") (list b "B") (list c "C") (list d "D"))
    (pool:text (pool:v+ (car fq)
                        (pool:v* (pool:unit (pool:v- (car fq) cen)) (* 1.5 th)))
               th (cadr fq) "POOL-NOTES"))

  ;; -------- report: one block per end, in its own sheet's letters
  (defun mu:endrows (nm style res ends pbot ptop pb2 sraw s1raw vraw
                     s2raw rraw / bad out)
    (setq bad (if (nth 5 res) (list t) nil)
          out nil)
    (if (or (= style "Grecian") (= style "ROman"))
        (setq out (append out (list
          (append (list (strcat nm " S") sraw
                        (if (= style "Grecian")
                            (distance pbot pb2)
                            (distance (car ends) (pool:mid pbot ptop))))
                  bad)
          (append (list (strcat nm " S1") s1raw
                        (distance ptop (cadr ends))) bad)
          (append (list (strcat nm " V") vraw
                        (distance (cadr ends) (caddr ends))) bad)))))
    (if (= style "Grecian")
        (setq out (append out (list
          (append (list (strcat nm " S2") s2raw
                        (distance pb2 (caddr ends))) bad)))))
    (if (or (= style "ROman") (= style "Oval"))
        (setq out (append out (list
          (append (list (strcat nm " R") rraw (nth 4 ends)) bad)))))
    out)

  (setq rows (append
    (list (append (list "OV B" braw (distance tipl tipr))
                  (if muttbad (list t) nil))
          (list "OV A" araw (distance a d))
          (list "T SIDE" (- tv insl insr) (distance pdc0 pdc1)))
    (mu:endrows "DEEP" dstyle dres lend a d pab0
                dsraw ds1raw dvraw ds2raw drraw)
    (mu:endrows "SHAL" sstyle sres rend b c pab1
                ssraw ss1raw svraw ss2raw srraw)))
  (if (not pool:*insq*)
      (setq rows (append rows
                         (list (list "CROSS A-C" dac (nth 4 meas))
                               (list "CROSS B-D" dbd (nth 5 meas))))))

  ;; -------- interior: standard bottom pipeline, anchored tip to tip
  (setq rows (append rows (pool:hopmuttdsp quad tipl tipr doff th)))
  (if failed (setq notes (cons "CROSS DIMS FAILED" notes)))
  (setq notes (append notes pool:*valnotes*))
  (pool:report rows notes (+ xmax (* 2.0 doff)) ymax th "POOL-NOTES")
  (if failed
      (princ "\n*** CROSS DIMS FAILED -- sides held true, see report table ***")
      (princ "\nPool layout complete -- see the report table."))
  (princ))

;; Mutt bottom dispatcher: the standard rectangle pipeline on the
;; tip-to-tip frame (H closes from the deep tip, E to the shallow
;; tip, like every home sheet), square hopper corners, no corner
;; ties -- the ends are too varied to tie the hopper back to.
(defun pool:hopmuttdsp (quad tipl tipr doff th / btype u v)
  (if (not (pool:askyn "Add pool bottom (hopper) detail?" "Yes" nil))
      nil
      (progn
        (setq btype (pool:askkw "Bottom type" pool:*btypes* pool:*btshown*
                                "Normal" nil))
        (setq u (pool:unit (pool:v- tipr tipl))
              v (pool:perp u))
        (if (/= btype "Sport")
            (pool:hopnormal (pool:bodyquad (list tipl v) (list tipr v)
                                           (list (car quad)
                                                 (pool:v- (cadr quad) (car quad)))
                                           (list (cadddr quad)
                                                 (pool:v- (caddr quad) (cadddr quad))))
                            pool:*sq4* doff th nil btype
                            (min (car tipl) (car tipr))
                            (- (apply 'min (mapcar 'cadr quad)) (* 2.2 doff))
                            nil)
            (pool:hopsport (list tipl v) (list tipr v)
                           (list (car quad) (pool:v- (cadr quad) (car quad)))
                           (list (cadddr quad)
                                 (pool:v- (caddr quad) (cadddr quad)))
                           (pool:v* (pool:v+ (pool:v+ (car quad) (cadr quad))
                                             (pool:v+ (caddr quad) (cadddr quad)))
                                    0.25)
                           (distance tipl tipr)
                           (min (car tipl) (car tipr))
                           (- (apply 'min (mapcar 'cadr quad)) (* 2.2 doff))
                           (apply 'max (mapcar 'cadr quad))
                           doff th)))))

;; UNDO grouping that copes with drawings where undo is limited or
;; off, and with an error firing before the group was ever opened.
(defun pool:undobegin ()
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
      (progn
        (command "_.UNDO" "_Begin")
        (setq pool:*undogrp* t))))

(defun pool:undoend ()
  (if pool:*undogrp* (command "_.UNDO" "_End"))
  (setq pool:*undogrp* nil))

;;; -------------------- sysvar save / restore --------------------------
;;; The snapshot of the user's settings lives in a GLOBAL and is taken
;;; only when no snapshot is already pending: if a previous run died
;;; before restoring (hard crash, failure inside the error handler),
;;; the stale snapshot still holds the user's TRUE settings.  Saving
;;; again at that point would capture the zeroed OSMODE and every
;;; later run would faithfully "restore" 0 -- the user's object snaps
;;; would look permanently wiped by the command.  Restoring clears the
;;; snapshot so the next run saves fresh.

(defun pool:syssave ()
  (if (not pool:*sysold*)
      (setq pool:*sysold*
            (mapcar '(lambda (v) (cons v (getvar v)))
                    '("OSMODE" "LUNITS" "CMDECHO" "CLAYER")))))

(defun pool:sysrestore ( / v p)
  ;; OSMODE first -- object snaps are the setting the user misses most
  ;; if a cleanup is ever cut short partway
  (foreach v '("OSMODE" "LUNITS" "CMDECHO" "CLAYER")
    (setq p (assoc v pool:*sysold*))
    (if p (setvar v (cdr p))))
  (setq pool:*sysold* nil))

;;; -------------------- main command -----------------------------------

(defun c:POOL ( / *error* ptype base)

  (defun *error* (msg)
    (if (and msg
             (/= (strcase msg t) "function cancelled")
             (/= (strcase msg t) "quit / exit abort"))
        (princ (strcat "\nPOOL error: " msg)))
    ;; user settings come back FIRST so nothing below can skip them
    (pool:sysrestore)
    ;; DIMSTYLE is read-only to setvar, so it is put back the only way
    ;; it can be: dying inside a small-dim or cross-dim block must not
    ;; leave that style current in the user's drawing
    (pool:dimsend pool:*dimstyle0*)
    (pool:pvkill)
    (pool:undoend)
    (if *pop-error-mode* (*pop-error-mode*))
    (princ))

  ;; AutoCAD 2012+ requires this so *error* may call (command);
  ;; harmless no-op guard on older releases where it doesn't exist
  (if *push-error-using-command* (*push-error-using-command*))

  (pool:syssave)
  (setq pool:*valnotes* nil
        pool:*smallwarned* nil
        pool:*profents* nil
        pool:*dimstyle0* (getvar "DIMSTYLE"))
  (setvar "CMDECHO" 0)
  (pool:undobegin)
  ;; architectural units while prompting so every distance can be
  ;; typed as 25'6", 25'-6-1/2" or 25'6.5 as well as plain inches
  (setvar "LUNITS" 4)
  (princ "\nDistances may be typed as 25'6\", 25'-6-1/2\" or 25'6.5 (plain numbers = inches).")

  ;; In-square pools are built true to the side measurements and need
  ;; no diagonals; out-of-square pools take the usual cross-dim route.
  (setq pool:*insq*
        (= "Insquare"
           (pool:askkw "Is the pool in-square or out-of-square"
                       "Insquare Outofsquare" "Insquare/Outofsquare" nil nil)))
  (if pool:*insq*
      (princ "\nIn-square: building true to the side measurements (no cross dims needed)."))

  ;; L = true L; LAzyl = lazy L (type LA); ROman = roman (type RO)
  ;; the six common shapes first, then the rarely-used ones; type RO
  ;; for a roman, ROU for a round, MU for a mutt (mixed ends).
  (initget 1 "Rectangle Grecian ROman L LAzyl Oval OCtagon ROUnd MUtt")
  (setq ptype (getkword
                (strcat "\nPool shape [Rectangle/Grecian/ROman/L/LAzyl/Oval/"
                        "OCtagon/ROUnd/MUtt]: ")))

  ;; the base point is picked with the user's own snaps still live;
  ;; only afterwards do snaps drop for the command-fed drawing work
  (setq base (getpoint "\nInsertion base point <0,0>: ")
        pool:*base* (if base (list (car base) (cadr base)) (list 0.0 0.0)))
  (setvar "OSMODE" 0)

  ;; ------------------------------------------------ layers
  (pool:layer "POOL" 4)
  (pool:layer "DIMENSION" 2)
  (pool:layer "POOL-NOTES" 3)

  ;; dashed linetype up front so the guide's cross dims draw dashed
  ;; patterns are defined in inches and scaled to cancel LTSCALE, so
  ;; they show the same in any drawing
  (setq pool:*dashlt* (pool:ltload "DASHED")
        pool:*dotlt* (pool:ltload "DOT"))

  (cond
    ((= ptype "L") (pool:hexflow nil))
    ((= ptype "LAzyl") (pool:hexflow t))
    ((= ptype "Grecian") (pool:grecflow nil))
    ((= ptype "OCtagon") (pool:grecflow t))
    ((= ptype "ROman") (pool:romanflow))
    ((= ptype "ROUnd") (pool:roundflow))
    ((= ptype "MUtt") (pool:muttflow))
    (t (pool:quadflow ptype)))

  ;; ------------------------------------------------ finish
  (command "_.ZOOM" "_Extents")
  (pool:undoend)
  (pool:sysrestore)
  (if *pop-error-mode* (*pop-error-mode*))
  (princ))


(princ "\nPOOL.LSP loaded.  Type POOL to lay out a pool.")
(princ)
