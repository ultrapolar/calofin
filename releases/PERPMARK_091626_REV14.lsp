;;; ======================================================================
;;; PERPMARK.lsp  --  measured distances marked square off the pool wall,
;;;                   then joined into one polyline and dimensioned
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  PERPMARK     mark measured distances off the perimeter
;;;            PERPMARKVER  print the loaded version
;;; ======================================================================
;;;
;;; What it is for
;;;   A bench, a step, a tanning ledge and a gutter are all measured the
;;;   same way in the field: stand at a survey point on the wall, run the
;;;   tape square off it, and write the number down beside that point's
;;;   number.  PERPMARK is that, at the keyboard.  Name the point -- click
;;;   it or type its number -- give the distance, and the point gets a
;;;   circle of that radius, the swing of the tape, and a line of that
;;;   length running square off the wall into the pool.  Name the next
;;;   point, type the next number, and so on for as long as the sheet
;;;   lasts.  Enter ends it.
;;;
;;;   Then, if the marks are meant to BE something, it will join them up:
;;;   one polyline through the far end of every line between the two
;;;   points you name, the circles cleared away, and each line replaced
;;;   by the dimension that says what it measured.
;;;
;;;   The points are the ones the rest of the family reads -- ABHD,
;;;   CABHD, ABFIND, BPCALLOUT, CDCALLOUT and LHD all classify a survey
;;;   point the same way, and this uses their classifier: an "ab_pt"
;;;   INSERT wherever it sits, any other INSERT on the POINTS layer, and
;;;   a plain POINT on that layer, numbered by its "number" attribute.
;;;
;;; Workflow
;;;   1. Select the perimeter -- the wall the distances were taped off.
;;;      Any curve: a polyline (arc segments included), a line, an arc, a
;;;      circle, and anything else AutoCAD can measure along.
;;;   2. Click the centre of the pool.  That is the whole of the direction
;;;      question: a mark runs square off the wall toward the side the
;;;      centre is on, so nothing has to be answered per point.  It is the
;;;      one pick in the command that is a place rather than a point.
;;;   3. Name a survey point, give the distance, and repeat:
;;;        - click the point, or type its number; "17", "Pt.17", "#17"
;;;          and "017" all name the same one;
;;;        - a point that is not ON the perimeter is projected onto it,
;;;          and the mark is drawn from where it landed, so a shot that
;;;          sits an inch off the fitted wall still marks the wall;
;;;        - naming a point already marked REPLACES its mark -- the sheet
;;;          has one distance at a point, so the second answer is a
;;;          correction rather than a second mark;
;;;        - Back takes the last mark away again;
;;;        - Enter ends the round.
;;;   4. Draw a polyline through the marks?  No leaves every circle and
;;;      every line exactly where they are, for you to do as you see fit.
;;;   5. Yes asks which point the run starts at and which it ends at,
;;;      named the same way.  A point that was taped is the mark made at
;;;      it, so the run starts where the tape reached; a point that was
;;;      NOT taped measures zero and the run starts on the wall itself,
;;;      which is how a step that dies back into the wall is drawn.  The
;;;      two may be named in either order -- the marks say which way
;;;      round the run goes (below) -- and a tie, and only a tie, asks
;;;      for one click to settle it.
;;;   6. Last, the dimension style -- STANDARD INCHES or SIDE STANDARD,
;;;      the question PERPPTS and CPERPPTS ask in the same words.  It is
;;;      put only when there is a polyline to draw, so a pair of ends
;;;      with nothing between them is reported instead of being asked a
;;;      question it would throw away.
;;;   7. The polyline goes in on the perimeter's own layer and properties,
;;;      every circle is erased, and every line becomes a dimension in
;;;      that style on layer "DIMENSION".
;;;
;;; How the direction is found
;;;   Each mark's base point is the point of the perimeter closest to the
;;;   survey point.  The perimeter's tangent there, turned 90 degrees,
;;;   gives the two ways a mark could run; the one whose direction agrees
;;;   with "toward the centre click" is the one used.  It is measured per
;;;   mark rather than fixed once, so a run of marks around a corner or
;;;   along a radius each come off their own piece of wall square.
;;;
;;;   That makes the centre click a direction, not a datum: it is never
;;;   measured from and it does not have to be the true centroid.  What it
;;;   has to be is unambiguously INSIDE, which on a deeply notched shape
;;;   (a narrow L, a keyhole) is worth a thought before clicking -- see
;;;   the README's limitations.
;;;
;;; The order the polyline runs in
;;;   Marks are kept with their STATION -- how far along the perimeter,
;;;   measured from its start, the base point sits -- so the polyline runs
;;;   along the wall in the order the wall does, whatever order the points
;;;   were named in.
;;;
;;;   What decides whether a run end IS one of the marks is the survey
;;;   point's own identity, never how close the two landed.  That is the
;;;   whole reason the pick is a point rather than a place: two shots a
;;;   quarter inch apart are still two shots, and the sheet says which.
;;;
;;; Which way round a closed wall -- and why it is not asked
;;;   Two ends cut a closed perimeter into two arcs, and the run is one
;;;   of them.  Which one is decided by the MARKS, not by the order the
;;;   two ends were named: every mark sits on exactly one arc, so the arc
;;;   carrying more of them is the run that was measured.  Naming the
;;;   ends the other way round therefore gives the same run, read from
;;;   whichever end was named first.
;;;
;;;   It used to go forward from the start station whatever was on the
;;;   way, so naming the ends the other way round sent the run round the
;;;   empty side of the pool and handed back a two-point line straight
;;;   across it, with every measurement left off.
;;;
;;;   The one case the marks cannot settle is a genuine tie -- the same
;;;   number on each arc -- and that is the only time the question is
;;;   put: one click on a spot the run passes through, which is a
;;;   direction like the centre click and not a datum.  A tie needs at
;;;   least two marks to be a tie, and marks that ARE the two ends do not
;;;   vote (an end sits on both arcs), so an ordinary run never sees it.
;;;
;;;   A mark the run does not reach is NAMED before the drawing is done
;;;   -- "Pt.7 and Pt.9 sit outside the run" -- and is still marked and
;;;   still dimensioned.  A measurement is the one thing that may never
;;;   go quietly missing.
;;;
;;; Properties
;;;   * Circles and lines land on layer "PERPMARK" (created if missing).
;;;     They are the run's working marks: keep them, turn the layer off,
;;;     or let step 5 clear them.
;;;   * The joined polyline takes the layer, colour, linetype, lineweight
;;;     and linetype scale of the perimeter it was measured off.
;;;   * Dimensions go on layer "DIMENSION" in the style picked at step 6
;;;     when the drawing has it; otherwise the current style is used and
;;;     a note is printed.
;;;
;;; Robustness
;;;   * The whole run is one UNDO group: a single U reverses all of it.
;;;   * Esc or an error at any prompt restores every system variable the
;;;     command changed (OSMODE, CMDECHO, CLAYER and the dimension style)
;;;     and closes the UNDO group.
;;;   * A number nothing carries, a number two points share, a click on
;;;     nothing, a point the perimeter cannot be read under, and a centre
;;;     click that leaves the direction ambiguous all re-prompt where
;;;     they stand instead of guessing.
;;;   * All geometry is worked in WCS and converted at the edges, so the
;;;     command behaves under a rotated or shifted UCS.
;;;
;;; License: GPL-3.0-or-later
;;; ----------------------------------------------------------------------

(vl-load-com)

;; Version banner: tools/release_lisp.py reads it to stamp the dated
;; REV twin in releases/ (vN.M -> _MMDDYY_REVNM).
(setq *perpmark-version* "v1.4")

;;; ----------------------------------------------------------------------
;;;  Tunables
;;; ----------------------------------------------------------------------

;; Layer the circles and the perpendicular lines are drawn on.  Change it
;; to put the run's working marks somewhere a plot style already hides.
(setq pm:*marklayer* "PERPMARK")

;; ACI colour that layer is CREATED with, on a drawing that lacks it.  A
;; number, not 'auto: these marks are the measurement record and are
;; meant to be seen, so they take a colour that reads on any background
;; rather than one that recedes into it.
(setq pm:*markcolor* 1)

;; Layer and creation colour for the dimensions step 6 leaves behind.
(setq pm:*dimlayer* "DIMENSION")
(setq pm:*dimcolor* 7)

;; The two dimension styles step 6 offers, and their order in the
;; question: STandard is the Enter answer.  PERPPTS and CPERPPTS ask the
;; same question in the same words, so a shop that renames a style
;; renames it here and the prompt follows -- the two KEYWORDS stay
;; STandard and SIde, which is the vocabulary all three share.  A
;; drawing that has neither keeps its current style and is told so.
(setq pm:*dimstyle-std*  "STANDARD INCHES")
(setq pm:*dimstyle-side* "SIDE STANDARD")

;; What counts as a survey point.  The classifier is the one BPCALLOUT,
;; CDCALLOUT, ABFIND and LHD share: change it in all of them or the
;; tools disagree about what the drawing holds.
(setq pm:*point-block* "ab_pt")    ; block name whose INSERTs mark
                                   ; points wherever they sit
(setq pm:*point-layer* "POINTS")   ; layer whose POINTs and INSERTs are
                                   ; always points, whatever block
(setq pm:*pt-tag* "number")        ; attribute tag on the point block
                                   ; naming the point.  A block without
                                   ; it lends its first attribute that
                                   ; reads as a number instead
(setq pm:*unknown* "?")            ; what a point with no readable
                                   ; number is called.  It can still be
                                   ; clicked; only a number can be typed
(setq pm:*pt-prefix* "Pt.")        ; how a point is named in the prompts
                                   ; and the report

;; A click within this of a survey point picks that point.  The number
;; typed at the same prompt never uses it -- a name is exact.  12.0 is
;; what BPCALLOUT and ABFIND snap at, so a drafter's aim carries between
;; the three.
(setq pm:*snap* 12.0)

;; Two points closer than this are one point: it keeps a zero-length
;; segment out of the joined polyline and a zero-length normal out of
;; the direction test.
(setq pm:*fuzz* 1e-6)

;;; ----------------------------------------------------------------------
;;;  Vectors and angles
;;;  Copied from CALOFIN-LIB.lsp under this file's own prefix, so the
;;;  standalone file loads alone -- see STANDARDS.md section 4.
;;; ----------------------------------------------------------------------

(defun pm:2d (p) (list (car p) (cadr p)))
(defun pm:v- (a b) (mapcar '- (pm:2d a) (pm:2d b)))
(defun pm:v+ (a b) (mapcar '+ (pm:2d a) (pm:2d b)))
(defun pm:v* (v s) (list (* (car v) s) (* (cadr v) s)))
(defun pm:dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))
(defun pm:perp (v) (list (- (cadr v)) (car v))) ; rotate 90 deg CCW
(defun pm:vlen (v) (sqrt (pm:dot v v)))

;; v scaled to length 1; nil for a (near-)zero vector.
(defun pm:unit (v / l)
  (setq v (pm:2d v)
        l (pm:vlen v))
  (if (> l 1e-12) (pm:v* v (/ 1.0 l))))

;; normalize an angle into [0, 2pi)
(defun pm:angnorm (a)
  (while (< a 0.0) (setq a (+ a pi pi)))
  (while (>= a (+ pi pi)) (setq a (- a pi pi)))
  a)

;; Tangent with the angle clamped just short of +/-90 degrees, so a
;; degenerate half-turn bulge yields a huge but finite number instead
;; of dividing by zero.
(defun pm:tan (x)
  (cond ((> x  1.5697) (setq x  1.5697))    ; 89.94 deg
        ((< x -1.5697) (setq x -1.5697)))
  (/ (sin x) (cos x)))

;;; ----------------------------------------------------------------------
;;;  The perimeter, as segments
;;;
;;;  The wall is walked as a list of segments read off the entity itself
;;;  rather than through vlax-curve-*, for one reason: the polyline step 6
;;;  builds has to run along the wall in the wall's own order, and that
;;;  order is each mark's STATION -- the distance along the perimeter of
;;;  its base point.  A segment walk hands that back as a by-product of
;;;  the projection it is doing anyway, where vlax-curve-getDistAtPoint
;;;  would be a second COM round trip per mark with its own failure mode.
;;;
;;;  LINE, ARC, CIRCLE and LWPOLYLINE are what a pool perimeter is drawn
;;;  as in this tree -- ABHD, POOL and ADAB all leave an LWPOLYLINE, arc
;;;  segments and all.  Anything else (a SPLINE traced off a drone photo,
;;;  an ELLIPSE, an old heavy POLYLINE) is measured through vlax-curve-*
;;;  instead, by pm:project-com below.
;;;
;;;  A segment is one of:
;;;     (S p1 p2)              a straight run from p1 to p2
;;;     (A ctr rad a0 sweep)   an arc of rad about ctr, starting at angle
;;;                            a0 and sweeping SIGNED sweep radians --
;;;                            positive counterclockwise, which is the
;;;                            sign a positive bulge carries
;;;  Every point in one is WCS, because that is what entget hands back.
;;; ----------------------------------------------------------------------

;; The segment p1 -> p2 carrying polyline bulge b.  A bulge is
;; tan(included/4), so the included angle is 4*atan(b) and its sign is
;; the direction of travel; the centre sits half a chord away along the
;; chord's normal, by (chord/2)/tan(included/2).
(defun pm:mkseg (p1 p2 b / inc ch r th d cx cy ctr)
  (setq inc (* 4.0 (atan b))
        ch  (distance (pm:2d p1) (pm:2d p2)))
  (if (or (< (abs b) 1e-12)
          (< ch 1e-12)
          (< (abs (sin (/ inc 2.0))) 1e-12))
    (list 'S (pm:2d p1) (pm:2d p2))
    (progn
      (setq r   (abs (/ ch (* 2.0 (sin (/ inc 2.0)))))
            th  (angle (pm:2d p1) (pm:2d p2))
            d   (/ (/ ch 2.0) (pm:tan (/ inc 2.0)))
            cx  (+ (/ (+ (car p1) (car p2)) 2.0)
                   (* d (cos (+ th (/ pi 2.0)))))
            cy  (+ (/ (+ (cadr p1) (cadr p2)) 2.0)
                   (* d (sin (+ th (/ pi 2.0)))))
            ctr (list cx cy))
      (list 'A ctr r (angle ctr (pm:2d p1)) inc))))

;; The vertices of an LWPOLYLINE as (point bulge), in order.  entget
;; hands the groups back in order, so a 42 belongs to the 10 in front of
;; it; a vertex with no 42 carries no bulge.
(defun pm:lwverts (ed / vs g)
  (setq vs '())
  (foreach g ed
    (cond
      ((= 10 (car g)) (setq vs (cons (list (pm:2d (cdr g)) 0.0) vs)))
      ((and (= 42 (car g)) vs)
       (setq vs (cons (list (car (car vs)) (cdr g)) (cdr vs))))))
  (reverse vs))

;; EN as a list of segments, or nil when nothing here can read it.
(defun pm:segs (en / ed typ vs closed n i out a0 a1 sw v1 v2)
  (setq ed  (entget en)
        typ (cdr (assoc 0 ed))
        out '())
  (cond
    ((= typ "LINE")
     (list (list 'S (pm:2d (cdr (assoc 10 ed))) (pm:2d (cdr (assoc 11 ed))))))
    ((= typ "ARC")
     (setq a0 (cdr (assoc 50 ed))
           a1 (cdr (assoc 51 ed))
           sw (pm:angnorm (- a1 a0)))
     (if (< sw 1e-12) (setq sw (+ pi pi)))
     (list (list 'A (pm:2d (cdr (assoc 10 ed))) (cdr (assoc 40 ed)) a0 sw)))
    ((= typ "CIRCLE")
     (list (list 'A (pm:2d (cdr (assoc 10 ed))) (cdr (assoc 40 ed))
                 0.0 (+ pi pi))))
    ((= typ "LWPOLYLINE")
     (setq vs     (pm:lwverts ed)
           n      (length vs)
           closed (= 1 (logand 1 (cond ((cdr (assoc 70 ed))) (0))))
           i      0)
     (if (< n 2)
       nil
       (progn
         (while (< i (if closed n (1- n)))
           (setq v1  (nth i vs)
                 v2  (nth (rem (1+ i) n) vs)
                 out (cons (pm:mkseg (car v1) (car v2) (cadr v1)) out)
                 i   (1+ i)))
         (reverse out))))
    (t nil)))

(defun pm:seg-len (s)
  (if (eq (car s) 'S)
    (distance (cadr s) (caddr s))
    (* (caddr s) (abs (nth 4 s)))))

(defun pm:seg-start (s / ctr)
  (if (eq (car s) 'S)
    (cadr s)
    (progn
      (setq ctr (cadr s))
      (list (+ (car ctr)  (* (caddr s) (cos (nth 3 s))))
            (+ (cadr ctr) (* (caddr s) (sin (nth 3 s))))))))

(defun pm:seg-end (s / ctr a)
  (if (eq (car s) 'S)
    (caddr s)
    (progn
      (setq ctr (cadr s)
            a   (+ (nth 3 s) (nth 4 s)))
      (list (+ (car ctr)  (* (caddr s) (cos a)))
            (+ (cadr ctr) (* (caddr s) (sin a)))))))

;; The point of S closest to P.  A straight segment clamps the projection
;; to its ends; an arc takes the radial point when the direction of P
;; falls inside the sweep and the nearer end when it does not.
(defun pm:seg-closest (s p / a b d l t01 ctr r rel u)
  (setq p (pm:2d p))
  (if (eq (car s) 'S)
    (progn
      (setq a (cadr s)
            b (caddr s)
            d (pm:v- b a)
            l (pm:dot d d))
      (if (< l 1e-24)
        a
        (progn
          (setq t01 (/ (pm:dot (pm:v- p a) d) l))
          (cond ((< t01 0.0) (setq t01 0.0))
                ((> t01 1.0) (setq t01 1.0)))
          (pm:v+ a (pm:v* d t01)))))
    (progn
      (setq ctr (cadr s)
            r   (caddr s)
            u   (pm:unit (pm:v- p ctr)))
      (if (null u)
        (pm:seg-start s)
        (progn
          ;; how far into the sweep the direction of P lies, measured
          ;; the way the sweep runs
          (setq rel (pm:angnorm (* (if (< (nth 4 s) 0.0) -1.0 1.0)
                                   (- (angle ctr p) (nth 3 s)))))
          (if (<= rel (abs (nth 4 s)))
            (pm:v+ ctr (pm:v* u r))
            (if (< (distance p (pm:seg-start s))
                   (distance p (pm:seg-end s)))
              (pm:seg-start s)
              (pm:seg-end s))))))))

;; Unit tangent of S at Q (a point already on it), pointing the way the
;; segment travels.  nil on a segment with no length.
(defun pm:seg-tangent (s q / ctr rad)
  (if (eq (car s) 'S)
    (pm:unit (pm:v- (caddr s) (cadr s)))
    (progn
      (setq ctr (cadr s)
            rad (pm:unit (pm:v- q ctr)))
      (if (null rad)
        nil
        (pm:v* (pm:perp rad) (if (< (nth 4 s) 0.0) -1.0 1.0))))))

;; Arc length from the start of S to Q.
(defun pm:seg-station (s q / ctr rel)
  (if (eq (car s) 'S)
    (distance (cadr s) (pm:2d q))
    (progn
      (setq ctr (cadr s)
            rel (pm:angnorm (* (if (< (nth 4 s) 0.0) -1.0 1.0)
                               (- (angle ctr q) (nth 3 s)))))
      (if (> rel (abs (nth 4 s)))
        ;; past the far end: the clamp landed on one end or the other
        (if (< (distance (pm:2d q) (pm:seg-start s))
               (distance (pm:2d q) (pm:seg-end s)))
          0.0
          (pm:seg-len s))
        (* (caddr s) rel)))))

(defun pm:total (segs / tot s)
  (setq tot 0.0)
  (foreach s segs (setq tot (+ tot (pm:seg-len s))))
  tot)

;; T when the walk closes back on itself -- a circle, a closed polyline,
;; or a shape drawn open but ending where it started.
(defun pm:closed-p (segs)
  (and segs
       (< (distance (pm:seg-start (car segs))
                    (pm:seg-end (last segs)))
          1e-9)))

;; (base tangent station) for the point of SEGS closest to P, all WCS.
(defun pm:project (segs p / acc best bd s q d)
  (setq acc 0.0 best nil bd nil)
  (foreach s segs
    (setq q (pm:seg-closest s p)
          d (distance (pm:2d p) q))
    (if (or (null best) (< d bd))
      (setq best (list q (pm:seg-tangent s q) (+ acc (pm:seg-station s q)))
            bd   d))
    (setq acc (+ acc (pm:seg-len s))))
  (if (and best (cadr best)) best))

;;; ----------------------------------------------------------------------
;;;  The perimeter AutoCAD can measure but this file cannot read
;;;
;;;  A SPLINE, an ELLIPSE or a heavy POLYLINE has no segment list here,
;;;  so the same three numbers are asked of AutoCAD instead: the closest
;;;  point, the distance along to it, and the first derivative there for
;;;  the tangent.  Every call is caught -- a curve AutoCAD will not answer
;;;  for comes back nil and the pick is re-prompted, never half-measured.
;;; ----------------------------------------------------------------------

(defun pm:comcall (fn args / r)
  (setq r (vl-catch-all-apply fn args))
  (if (vl-catch-all-error-p r) nil r))

(defun pm:project-com (en p / q prm st dv tg)
  (setq q (pm:comcall 'vlax-curve-getClosestPointTo (list en (pm:2d p))))
  (if (null q)
    nil
    (progn
      (setq st  (pm:comcall 'vlax-curve-getDistAtPoint (list en q))
            prm (pm:comcall 'vlax-curve-getParamAtPoint (list en q)))
      (if (null prm)
        nil
        (progn
          (setq dv (pm:comcall 'vlax-curve-getFirstDeriv (list en prm))
                tg (if dv (pm:unit dv)))
          (if (or (null tg) (null st))
            nil
            (list (pm:2d q) tg st)))))))

;; Either reader, whichever this perimeter answers to.
(defun pm:locate (en segs p)
  (if segs (pm:project segs p) (pm:project-com en p)))

(defun pm:runlen (en segs / prm r)
  (if segs
    (pm:total segs)
    (progn
      (setq prm (pm:comcall 'vlax-curve-getEndParam (list en))
            r   (if prm (pm:comcall 'vlax-curve-getDistAtParam
                          (list en prm))))
      (if (numberp r) r 0.0))))

(defun pm:isclosed (en segs)
  (if segs
    (pm:closed-p segs)
    (if (pm:comcall 'vlax-curve-isClosed (list en)) T)))

;;; ----------------------------------------------------------------------
;;;  Lists
;;; ----------------------------------------------------------------------

;; LST sorted ascending on the car of each element, stably.  vl-sort is
;; not used on purpose: it DROPS items that compare equal, which here
;; would silently lose a mark that shares a station with another.
(defun pm:sortkey (lst / out e head)
  (setq out '())
  (foreach e lst
    (setq head '())
    (while (and out (<= (car (car out)) (car e)))
      (setq head (cons (car out) head)
            out  (cdr out)))
    (setq out (cons e out))
    (while head
      (setq out  (cons (car head) out)
            head (cdr head))))
  out)

;;; ----------------------------------------------------------------------
;;;  Layers and drawing
;;; ----------------------------------------------------------------------

;; Create the output layer, or - when it already exists - make sure it is
;; on, thawed and unlocked.  Without this a successful run onto a frozen
;; or switched-off layer looks like the command did nothing.  (The
;; canonical body of STANDARDS section 5; the grouped build swaps the
;; whole helper for cal:ensure-layer, so the wording of the repair notice
;; is the library's and not this tool's.)
(defun pm:ensure-layer (name color / rec ed flags col fixed)
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

(defun pm:circle (ctr r lay)
  (entmakex (list '(0 . "CIRCLE") '(100 . "AcDbEntity") (cons 8 lay)
                  '(100 . "AcDbCircle")
                  (cons 10 (list (car ctr) (cadr ctr) 0.0))
                  (cons 40 r))))

(defun pm:line (a b lay)
  (entmakex (list '(0 . "LINE") '(100 . "AcDbEntity") (cons 8 lay)
                  '(100 . "AcDbLine")
                  (cons 10 (list (car a) (cadr a) 0.0))
                  (cons 11 (list (car b) (cadr b) 0.0)))))

;; The groups that carry an entity's look, for the joined polyline to
;; inherit from the perimeter it was measured off.
(defun pm:props (ed / out g)
  (setq out '())
  (foreach g '(62 420 6 370 48)
    (if (assoc g ed) (setq out (cons (assoc g ed) out))))
  (reverse out))

(defun pm:pline (pts ed / e p)
  (setq e (append (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity")
                        (cons 8 (cdr (assoc 8 ed))))
                  (pm:props ed)
                  (list '(100 . "AcDbPolyline")
                        (cons 90 (length pts)) '(70 . 0))))
  (foreach p pts
    (setq e (append e (list (cons 10 (list (car p) (cadr p)))))))
  (entmakex e))

(defun pm:erase (e)
  (if (and e (entget e)) (entdel e)))

;;; ----------------------------------------------------------------------
;;;  The survey points
;;;
;;;  A distance off the wall is taped AT a point -- one of the numbered
;;;  shots ABHD, CABHD and the rest of the family read -- so a point is
;;;  what this command marks, and its number is what names it.  The
;;;  classifier below is BPCALLOUT's, shared with CDCALLOUT, ABFIND and
;;;  LHD: an ab_pt INSERT wherever it sits, any other INSERT on the
;;;  POINTS layer, and a plain POINT on that layer.
;;;
;;;  A point with no readable number is carried as "?" rather than
;;;  dropped: it can be clicked like any other, it just cannot be typed.
;;; ----------------------------------------------------------------------

;; What the routine knows about one survey point: where it is, what it
;; is called, and the entity it is.  The entity is its IDENTITY -- it is
;; how a second pick of the same point is known to be a re-mark, and how
;; a run end is known to be a mark already made.
(defun pm:cd-pt (c) (car c))        ; (x y)
(defun pm:cd-nm (c) (cadr c))       ; "17"
(defun pm:cd-en (c) (caddr c))      ; the INSERT (or POINT) it was read from

;; "Pt.17", the way the prompts and the report name a point.
(defun pm:ptname (nm) (strcat pm:*pt-prefix* nm))

;; The name carried by a point block, read from its pm:*pt-tag*
;; attribute; when the block has no such attribute, the first attribute
;; whose value reads as a number is taken instead (survey exports do not
;; all use the ab_pt tag).  nil when neither exists.
(defun pm:block-number (en / sub ed val fall v)
  (setq sub (entnext en) val nil fall nil)
  (while (and sub
              (setq ed (entget sub))
              (= "ATTRIB" (cdr (assoc 0 ed))))
    (setq v (cdr (assoc 1 ed)))
    (if (and (null val)
             (cdr (assoc 2 ed))
             (= (strcase (cdr (assoc 2 ed))) (strcase pm:*pt-tag*)))
      (setq val v))
    (if (and (null fall) v (distof v 2))
      (setq fall v))
    (setq sub (entnext sub)))
  (if val val fall))

;; Every survey point in the drawing, as (position name entity).
(defun pm:collect-points ( / ss i en ed typ p nm out)
  (setq out nil
        ss  (ssget "_X" '((0 . "INSERT,POINT"))))
  (if ss
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq en  (ssname ss i)
              ed  (entget en)
              typ (cdr (assoc 0 ed))
              p   (cdr (assoc 10 ed))
              nm  nil)
        (cond
          ((= typ "INSERT")
           (if (or (= (strcase (cdr (assoc 2 ed)))
                      (strcase pm:*point-block*))
                   (= (strcase (cdr (assoc 8 ed)))
                      (strcase pm:*point-layer*)))
             (progn
               (setq nm (pm:block-number en))
               (setq out (cons (list (list (car p) (cadr p))
                                     (if (and nm (/= nm "")) nm pm:*unknown*)
                                     en)
                               out)))))
          ((= typ "POINT")
           (if (= (strcase (cdr (assoc 8 ed)))
                  (strcase pm:*point-layer*))
             (setq out (cons (list (list (car p) (cadr p)) pm:*unknown* en)
                             out)))))
        (setq i (1+ i)))))
  (reverse out))

;; The NUMBER a typed point name carries: the spelling with the spaces,
;; the hashes and the "Pt." prefix taken off, and nothing else touched.
;; Only the dot right after PT is a prefix dot - a point genuinely named
;; "40.5" keeps its decimal.  (ABFIND's abf:as-number.)
(defun pm:as-number (s / out i ch)
  (setq out "" i 1)
  (while (<= i (strlen s))
    (setq ch (substr s i 1))
    (if (not (member ch '(" " "#")))
      (setq out (strcat out ch)))
    (setq i (1+ i)))
  (if (and (>= (strlen out) 2) (= (strcase (substr out 1 2)) "PT"))
    (progn
      (setq out (substr out 3))
      (if (= (substr out 1 1) ".") (setq out (substr out 2)))))
  out)

;; One comparable form for a point number, so "35", "Pt.35", "pt 35",
;; "#35" and "035" all meet in the middle.  (ABFIND's abf:canon.)
(defun pm:canon (s)
  (setq s (pm:as-number (strcase s)))
  (if (distof s 2)
    (rtos (distof s 2) 2 8)
    s))

;; The survey point nearest PK, when one sits within pm:*snap* of it.
(defun pm:nearest (pk cands / best bd c d)
  (setq best nil bd nil)
  (foreach c cands
    (setq d (distance (pm:2d pk) (pm:cd-pt c)))
    (if (and (<= d pm:*snap*) (or (null bd) (< d bd)))
      (setq best c bd d)))
  best)

;; Every point whose number is the one typed.  More than one is a sheet
;; that numbers two points the same, and is asked about rather than
;; guessed at.
(defun pm:matches (s cands / want out c)
  (setq want (pm:canon s) out nil)
  (foreach c cands
    (if (= (pm:canon (pm:cd-nm c)) want) (setq out (cons c out))))
  (reverse out))

;;; ----------------------------------------------------------------------
;;;  Ask helpers
;;;  Copied from CALOFIN-LIB.lsp under this file's own prefix, so the
;;;  standalone file loads alone -- see STANDARDS.md section 4.
;;;  Back sentinel: PM-BACK.
;;; ----------------------------------------------------------------------

;; Keyword question.  kws is the initget list, shown the bracketed text,
;; dflt the Enter answer (nil = an answer is required).  Returns the
;; keyword or PM-BACK.  Undo is accepted everywhere Back is, unlisted.
(defun pm:askkw (msg kws shown dflt back / v)
  (initget (if dflt 0 (if back 0 1))
           (if back (strcat kws " Back Undo") kws))
  (setq v (getkword (strcat "\n" msg " [" shown
                            (if back "/Back" "") "]"
                            (if dflt (strcat " <" dflt ">") "") ": ")))
  (if lzd:ask (lzd:ask msg v) v)
  (cond ((member v '("Back" "Undo")) 'PM-BACK)
        ((null v) (if dflt dflt (pm:askkw msg kws shown dflt back)))
        (t v)))

;; Yes/No.  dflt is "Yes" or "No" and is always shown.  Returns T, nil
;; or PM-BACK.
(defun pm:askyn (msg dflt back / v)
  (setq v (pm:askkw msg "Yes No" "Yes/No" dflt back))
  (if (eq v 'PM-BACK) v (= v "Yes")))

;; Distance entry with the kind system of STANDARDS.md section 3.
;; Returns the number, nil for NA, or PM-BACK.
(defun pm:askdist (kind msg dflt back / v kw)
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
  (if lzd:ask (lzd:ask msg v) v)
  (cond ((and (= (type v) 'STR) (member v '("Back" "Undo"))) 'PM-BACK)
        ((= (type v) 'STR) nil)               ; NA
        ((and (null v) (eq kind 'SUG)) dflt)  ; Enter took the suggestion
        (t v)))

;; A PLACE, in the current UCS -- the centre click, and nothing else in
;; this command.  Always required: Enter re-asks.  Returns the point or
;; PM-BACK.  (A survey point is pm:askpoint below, which is a different
;; question: it names one of the drawing's own points.)
(defun pm:askpt (msg back / v)
  (if back (initget 1 "Back Undo") (initget 1))
  (setq v (getpoint (strcat "\n" msg (if back " [Back]" "") ": ")))
  (if lzd:ask (lzd:ask msg v) v)
  (if (and (= (type v) 'STR) (member v '("Back" "Undo"))) 'PM-BACK v))

;; A survey point, clicked or typed.  One prompt takes both: (initget
;; 128) is arbitrary input, which hands typed text back from getpoint as
;; the string it is where a click comes back as the point it is.  The
;; misses are re-asked HERE rather than unwinding the caller's chain --
;; a number nothing carries and a click on nothing are typos, not
;; answers, and the question they belong to is this one.  tail is the
;; prose inside the angle brackets on a loop prompt whose Enter ends the
;; loop (nil = a point is required).  Returns the candidate, nil for
;; Enter, or PM-BACK.
(defun pm:askpoint (msg tail back cands / v out done dupes)
  (setq done nil out nil)
  (while (not done)
    (if back
      (initget (if tail 128 129) "Back Undo")
      (initget (if tail 128 129)))
    (setq v (getpoint (strcat "\n" msg
                              (if back " [Back]" "")
                              (if tail (strcat " <" tail ">") "")
                              ": ")))
    (if lzd:ask (lzd:ask msg v) v)
    (cond
      ((null v)
       (if tail
         (setq out nil done T)
         (princ "\nA survey point is required - click one, or type its number.")))
      ((and (= (type v) 'STR) (member v '("Back" "Undo")))
       (setq out 'PM-BACK done T))
      ((= (type v) 'STR)
       (setq dupes (pm:matches v cands))
       (cond
         ((null dupes)
          (princ (strcat "\nNo survey point is numbered \""
                         (pm:as-number v)
                         "\" - try again, or click the point itself.")))
         ((> (length dupes) 1)
          (princ (strcat "\n" (itoa (length dupes)) " points are numbered \""
                         (pm:as-number v)
                         "\" - click the one you mean.")))
         (t (setq out (car dupes) done T))))
      (t
       (setq out (pm:nearest v cands))
       (if out
         (setq done T)
         (princ (strcat "\nNo survey point there - click one, or type"
                        " its number."))))))
  out)

;;; ----------------------------------------------------------------------
;;;  System variables
;;; ----------------------------------------------------------------------

(setq pm:*sysold* nil)

;; OSMODE is deliberately NOT in this list.  PERPMARK never
;; changes it, and a list is a promise to WRITE the value back: the run
;; would put its opening snapshot back over any snap the drafter ticked
;; on while it was up -- on a clean exit, with no error involved, which
;; is the likeliest way anyone meets it.  Borrow only what you move.
(defun pm:sysvars () '("CMDECHO" "CLAYER"))

(defun pm:syssave ( / v)
  (if (not pm:*sysold*)
    (setq pm:*sysold*
          (mapcar '(lambda (v) (cons v (getvar v))) (pm:sysvars)))))

(defun pm:sysrestore ( / v p)
  ;; OSMODE first -- object snaps are the setting the user misses most
  ;; if a run is ever cut short partway
  (foreach v (pm:sysvars)
    (setq p (assoc v pm:*sysold*))
    (if p (setvar v (cdr p))))
  (setq pm:*sysold* nil))

;; One undo group per command, in the one casing (STANDARDS section 5).
;; Opens only while undo is recording - _Begin in a drawing with UNDO off
;; (bit 1 of UNDOCTL clear) errors out of the command - and returns nil
;; then, so the caller skips the close it does not own.
(defun pm:undobegin ()
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn (command "_.UNDO" "_Begin") T)))

(defun pm:undoend ()
  (command "_.UNDO" "_End")
  nil)

;;; ----------------------------------------------------------------------
;;;  The marks
;;;
;;;  One mark is (station base offs dist circle line name ent):
;;;    station  how far along the perimeter its base point sits
;;;    base     the point ON the perimeter the tape was run from
;;;    offs     where the tape reached -- base + dist square off the wall
;;;    dist     the measurement (0.0 for a run end that was never taped)
;;;    circle   the swing of the tape, an ename (nil on a zero station)
;;;    line     the measurement itself, an ename (nil on a zero station)
;;;    name     the survey point's number, for the prompts and the report
;;;    ent      the survey point itself, which is the mark's IDENTITY:
;;;             picking that point again is a re-mark, and naming it at
;;;             a run end is naming this mark
;;; ----------------------------------------------------------------------

;; A run end at a point that was never taped: it sits ON the wall, so
;; its offset is its base and it carries no circle and no line.
(defun pm:mk-station (station base name ent)
  (list station base base 0.0 nil nil name ent))

(defun pm:m-station (m) (car m))
(defun pm:m-base (m) (cadr m))
(defun pm:m-offs (m) (caddr m))
(defun pm:m-dist (m) (nth 3 m))
(defun pm:m-circle (m) (nth 4 m))
(defun pm:m-line (m) (nth 5 m))
(defun pm:m-name (m) (nth 6 m))
(defun pm:m-ent (m) (nth 7 m))

;; Which way a mark at BASE runs: square off the wall, on the side CTR is.
;; nil when the tangent is unreadable or the centre click leaves the two
;; sides tied -- both are re-prompts, never a guess.
(defun pm:inward (tg base ctr / n side)
  (setq n (if tg (pm:unit (pm:perp tg))))
  (if (null n)
    nil
    (progn
      (setq side (pm:dot n (pm:v- ctr base)))
      (cond ((> side  pm:*fuzz*) n)
            ((< side (- pm:*fuzz*)) (pm:v* n -1.0))
            (t nil)))))

;; d wrapped into [0, tot) -- how far FORWARD along a closed perimeter,
;; so a run that crosses the polyline's own seam is one stretch and not
;; two.
(defun pm:wrap (d tot)
  (if (< tot 1e-12)
    0.0
    (progn
      (while (< d 0.0) (setq d (+ d tot)))
      (while (>= d tot) (setq d (- d tot)))
      d)))

;; The marks the run passes through, in the order the wall runs.
;;
;; s0 and s1 are the run's ends.  On an OPEN perimeter there is one
;; stretch between them and that is the run, read from s0 toward s1.  On
;; a CLOSED one there are two arcs, and BACK says which: nil walks
;; forward from s0 (wrapping past the polyline's own seam if that is the
;; way the ends point), T walks the other way round.  Either way the run
;; is handed back starting at s0, because that is the end the drafter
;; named first.
(defun pm:span (marks s0 s1 closed tot back / out m k span)
  (setq out '())
  (cond
    ((and closed back)
     ;; the far arc: how far each mark sits FORWARD of s1, turned round
     ;; so the run still reads from s0
     (setq span (pm:wrap (- s0 s1) tot))
     (foreach m marks
       (setq k (pm:wrap (- (pm:m-station m) s1) tot))
       (if (<= k (+ span pm:*fuzz*))
         (setq out (cons (cons (- span k) m) out)))))
    (closed
     (setq span (pm:wrap (- s1 s0) tot))
     (foreach m marks
       (setq k (pm:wrap (- (pm:m-station m) s0) tot))
       (if (<= k (+ span pm:*fuzz*)) (setq out (cons (cons k m) out)))))
    (t
     (foreach m marks
       (setq k (- (pm:m-station m) s0))
       (if (< s1 s0) (setq k (- k)))
       (if (and (>= k (- pm:*fuzz*))
                (<= k (+ (abs (- s1 s0)) pm:*fuzz*)))
         (setq out (cons (cons k m) out))))))
  (mapcar 'cdr (pm:sortkey out)))

;; Which way round a CLOSED perimeter the run goes, decided by the MARKS
;; rather than by the order the two ends happened to be named.
;;
;; Two ends cut a closed wall into two arcs and every mark sits on
;; exactly one of them, so the arc carrying more of them is the run the
;; drafter measured: naming the ends the other way round used to send the
;; run the other way and quietly leave every mark off it.  Returns nil
;; for the near arc (forward from s0), T for the far one, and 'ASK when
;; the two arcs hold the same number and nothing here can choose.
;;
;; A mark AT one of the ends is the end, not a vote: it sits on both
;; arcs and would only ever pad the count.
(defun pm:whichway (marks s0 s1 tot m0 m1 / near far span m k)
  (setq span (pm:wrap (- s1 s0) tot) near 0 far 0)
  (foreach m marks
    (if (not (or (eq (pm:m-ent m) (pm:m-ent m0))
                 (eq (pm:m-ent m) (pm:m-ent m1))))
      (progn
        (setq k (pm:wrap (- (pm:m-station m) s0) tot))
        (if (<= k (+ span pm:*fuzz*))
          (setq near (1+ near))
          (setq far (1+ far))))))
  (cond ((> near far) nil)
        ((> far near) T)
        ;; nothing to place: every mark IS one of the two ends, so both
        ;; arcs give the same two-point run and there is nothing to ask
        ((= 0 near) nil)
        (t 'ASK)))

;; T when station ST sits on the FAR arc -- the answer the middle click
;; gives when the marks could not.
(defun pm:far-side-p (st s0 s1 tot)
  (> (pm:wrap (- st s0) tot) (+ (pm:wrap (- s1 s0) tot) pm:*fuzz*)))

;; The marks the run does not pass through, named in the order they were
;; taped, so a measurement is never quietly left off the drawing.
(defun pm:left-out (marks run / out m r hit)
  (setq out '())
  (foreach m (reverse marks)
    (setq hit nil)
    (foreach r run
      (if (eq (pm:m-ent r) (pm:m-ent m)) (setq hit T)))
    (if (not hit) (setq out (cons (pm:ptname (pm:m-name m)) out))))
  (reverse out))

;; "Pt.7", "Pt.7 and Pt.9", "Pt.7, Pt.9 and Pt.12".
(defun pm:andjoin (l last / n i out k)
  (setq n (length l) i 0 out "")
  (foreach k l
    (setq i (1+ i)
          out (cond ((= i 1) k)
                    ((and last (= i n)) (strcat out " and " k))
                    (t (strcat out ", " k)))))
  out)

;; What a run end names.  A point that was taped is the mark that was
;; made at it, so the run starts where the tape reached; a point that
;; was NOT taped is a station of its own measuring zero, which is how a
;; step that dies back into the wall is drawn.  It is the point's own
;; identity that decides which, never how close the two landed -- that
;; is the whole reason the pick is a point rather than a place.  nil
;; when the perimeter cannot be read under it at all.
;; The mark made at survey point ENT, when one was made.
(defun pm:marked-at (marks ent / hit m)
  (setq hit nil)
  (foreach m marks
    (if (eq (pm:m-ent m) ent) (setq hit m)))
  hit)

(defun pm:runend (en segs marks cand / hit loc)
  (setq hit (pm:marked-at marks (pm:cd-en cand)))
  (if hit
    hit
    (progn
      (setq loc (pm:locate en segs (pm:cd-pt cand)))
      (if loc
        (pm:mk-station (caddr loc) (car loc)
                       (pm:cd-nm cand) (pm:cd-en cand))))))

;; MARKS with the one made at ENT taken out, its circle and its line
;; erased with it.  Picking a point a second time is a correction, not a
;; second mark: the sheet has one distance at that point.
(defun pm:unmark (marks ent / out m)
  (setq out '())
  (foreach m marks
    (if (eq (pm:m-ent m) ent)
      (progn (pm:erase (pm:m-circle m)) (pm:erase (pm:m-line m)))
      (setq out (cons m out))))
  (reverse out))

;; PTS with each point that repeats its predecessor dropped, so the
;; joined polyline never carries a zero-length segment.  Consecutive-only
;; on purpose: two marks the same distance apart at opposite ends of the
;; pool are two marks, and cal:dedupe's any-kept-one test would drop one
;; of them.
(defun pm:dedupe (pts / out p)
  (setq out '())
  (foreach p pts
    (if (or (null out) (> (distance p (car out)) pm:*fuzz*))
      (setq out (cons p out))))
  (reverse out))

;; Every mark that measured something, dimensioned where its line was,
;; in the STYLE the drafter picked.  Returns how many went in.  The
;; style is restored by the caller -- it is one of the settings the
;; *error* handler owes the user.
(defun pm:dimension (marks style / n m)
  (setq n 0)
  (setvar "CLAYER" (pm:ensure-layer pm:*dimlayer* pm:*dimcolor*))
  (if (tblsearch "DIMSTYLE" style)
    (command "_.-DIMSTYLE" "_Restore" style)
    (princ (strcat "\nDimension style \"" style
                   "\" is not in this drawing - using the current style"
                   " instead.")))
  (foreach m (reverse marks)
    (if (> (pm:m-dist m) pm:*fuzz*)
      (progn
        ;; command arguments are read in the CURRENT UCS, and every mark
        ;; has been carried in WCS since the pick that made it
        (command "_.DIMALIGNED"
                 (trans (pm:m-base m) 0 1)
                 (trans (pm:m-offs m) 0 1)
                 (trans (pm:m-offs m) 0 1))
        (setq n (1+ n)))))
  n)

;;; ----------------------------------------------------------------------
;;;  Commands
;;; ----------------------------------------------------------------------

;; ahead of the command on purpose: the structural test scans from
;; c:PERPMARK to end-of-file for leaked variables, and a defun name there
;; would read as one
(defun c:PERPMARKVER ()
  (princ (strcat "\nPERPMARK " *perpmark-version*))
  (princ))

(defun c:PERPMARK (/ *error* undo-open
                     sel en ed segs tot closed ctr pick cand cands loc
                     base tg nrm d ans marks stage done pts run s0 s1
                     m0 m1 way wayasked miss sty lay odim ndims npts m)

  (defun *error* (msg)
    ;; user settings come back FIRST so nothing below can skip them
    (pm:sysrestore)
    ;; DIMSTYLE cannot be setvar'd back
    (if (and odim (tblsearch "DIMSTYLE" odim))
      (vl-catch-all-apply 'command-s (list "_.-DIMSTYLE" "_Restore" odim)))
    ;; command-s, never plain command: 2015+ engines reject (command)
    ;; inside *error* unless the error mode was pushed beforehand
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (setq undo-open nil)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nPERPMARK error: " msg)))
    (if lzd:report (lzd:report "PERPMARK" *perpmark-version* msg))
    (princ))

  (if lzd:begin (lzd:begin "PERPMARK" *perpmark-version*))
  (pm:syssave)
  (setvar "CMDECHO" 0)
  ;; one group for the whole run -- the marks are drawn as they are
  ;; answered, so anything less would take one U per circle
  (setq undo-open (pm:undobegin)
        odim      (getvar "DIMSTYLE")
        marks     '()
        stage     1
        done      nil)

  (while (not done)
    (cond

      ;; --- 1. the perimeter the distances were taped off ---------------
      ((= stage 1)
       (setq sel (entsel "\nSelect the pool perimeter: "))
       (if lzd:ask (lzd:ask "\nSelect the pool perimeter: " sel) sel)
       (if lzd:watch (lzd:watch sel) sel)
       (cond
         ((null sel)
          (princ "\nNothing selected - try again, or press Esc to quit."))
         (t
          (setq en   (car sel)
                ed   (entget en)
                segs (pm:segs en)
                tot  (pm:runlen en segs))
          (cond
            ((and (null segs)
                  (null (pm:project-com en (pm:2d (trans (cadr sel) 1 0)))))
             (princ (strcat "\nA " (cdr (assoc 0 ed))
                            " is not something PERPMARK can measure along"
                            " - select the pool wall.")))
            ((< tot 1e-9)
             (princ "\nThat perimeter has no length."))
            (t
             (setq closed (pm:isclosed en segs)
                   cands  (pm:collect-points))
             (if (null cands)
               (progn
                 (princ (strcat "\nNo survey points in this drawing -"
                                " PERPMARK marks the distances taped at"
                                " the numbered points ABHD and its family"
                                " read."))
                 (setq done T))
               (progn
                 (princ (strcat "\n" (itoa (length cands))
                                " survey point(s) found."))
                 (setq stage 2))))))))

      ;; --- 2. the centre, which is the whole direction question --------
      ((= stage 2)
       (princ (strcat "\nA mark runs square off the wall, toward the side"
                      " the centre is on."))
       (setq pick (pm:askpt "Click the centre of the pool" T))
       (cond
         ((eq pick 'PM-BACK) (setq stage 1))
         ((null pick)
          (princ "\nA point is required - click inside the pool."))
         (t (setq ctr   (pm:2d (trans pick 1 0))
                  stage 3))))

      ;; --- 3. name a survey point.  Enter ends the round; Back takes
      ;;        the last mark away again, and at the first one re-opens
      ;;        the centre click ---------------------------------------
      ((= stage 3)
       (setq cand (pm:askpoint "Pick a survey point, or type its number"
                               "Enter = done" T cands))
       (cond
         ((eq cand 'PM-BACK)
          (cond
            ((null marks)
             (princ "\nStepping back one question.")
             (setq stage 2))
            (t
             (princ (strcat "\nStepping back one point - "
                            (pm:ptname (pm:m-name (car marks))) " undone."))
             (setq marks (pm:unmark marks (pm:m-ent (car marks)))))))
         ((null cand)
          (if (null marks)
            (progn (princ "\nNothing marked.") (setq done T))
            (setq stage 4)))
         (t
          (setq loc (pm:locate en segs (pm:cd-pt cand)))
          (cond
            ((null loc)
             (princ (strcat "\nThe perimeter cannot be read under "
                            (pm:ptname (pm:cd-nm cand))
                            " - pick a point nearer the wall.")))
            (t
             (setq base (car loc)
                   tg   (cadr loc)
                   nrm  (pm:inward tg base ctr))
             (if (null nrm)
               (princ (strcat "\nWhich side the mark runs to is a tie at "
                              (pm:ptname (pm:cd-nm cand))
                              " - the centre lines up with the wall there."
                              "  Back at the first point re-opens the"
                              " centre click."))
               (setq stage 31)))))))

      ;; --- 3b. and the distance taped off it --------------------------
      ((= stage 31)
       (setq d (pm:askdist 'REQ
                 (strcat "Distance from the perimeter at "
                         (pm:ptname (pm:cd-nm cand)))
                 nil T))
       (cond
         ((or (eq d 'PM-BACK) (null d)) (setq stage 3))
         (t
          (if (null lay)
            (setq lay (pm:ensure-layer pm:*marklayer* pm:*markcolor*)))
          ;; a point picked twice is the sheet being corrected, not two
          ;; marks at one shot: the older one goes
          (if (pm:marked-at marks (pm:cd-en cand))
            (progn
              (princ (strcat "\n" (pm:ptname (pm:cd-nm cand))
                             " re-marked - the first distance goes."))
              (setq marks (pm:unmark marks (pm:cd-en cand)))))
          (setq marks (cons (list (caddr loc) base
                                  (pm:v+ base (pm:v* nrm d)) d
                                  (pm:circle base d lay)
                                  (pm:line base (pm:v+ base (pm:v* nrm d))
                                           lay)
                                  (pm:cd-nm cand) (pm:cd-en cand))
                            marks)
                stage 3))))

      ;; --- 4. join them up? -------------------------------------------
      ((= stage 4)
       (setq ans (pm:askyn "Draw a polyline through the marks?" "Yes" T))
       (cond
         ((eq ans 'PM-BACK) (setq stage 3))
         ((null ans)
          (princ (strcat "\n" (itoa (length marks)) " mark(s) left on layer"
                         " \"" pm:*marklayer* "\" - circles and lines both."))
          (setq done T))
         (t (setq stage 5))))

      ;; --- 5 and 6. where the run starts, and where it ends ------------
      ((= stage 5)
       (setq cand (pm:askpoint
                    "The point the run starts at, or type its number"
                    nil T cands))
       (cond
         ((eq cand 'PM-BACK) (setq stage 4))
         (t
          (setq m0 (pm:runend en segs marks cand))
          (if (null m0)
            (princ (strcat "\nThe perimeter cannot be read under "
                           (pm:ptname (pm:cd-nm cand))
                           " - pick a point nearer the wall."))
            (setq stage 6)))))

      ((= stage 6)
       (setq cand (pm:askpoint
                    "The point the run ends at, or type its number"
                    nil T cands))
       (cond
         ((eq cand 'PM-BACK) (setq stage 5))
         (t
          (setq m1 (pm:runend en segs marks cand))
          (cond
            ((null m1)
             (princ (strcat "\nThe perimeter cannot be read under "
                            (pm:ptname (pm:cd-nm cand))
                            " - pick a point nearer the wall.")))
            (t
             (setq s0 (pm:m-station m0)
                   s1 (pm:m-station m1))
             ;; which way round: the marks decide it wherever they can,
             ;; so the two ends can be named in either order
             (setq way (if closed
                         (pm:whichway marks s0 s1 tot m0 m1)
                         nil))
             ;; the style question sits behind whichever of these two was
             ;; the last one actually put (STANDARDS section 3: a chain
             ;; with a conditional step carries its direction)
             (setq wayasked (eq way 'ASK))
             (if wayasked (setq stage 7) (setq stage 8)))))))

      ;; --- 7. the two arcs hold the same number of marks, so only the
      ;;        drafter can say which way the run passes ---------------
      ((= stage 7)
       (princ (strcat "\nThe run's two ends cut the wall in half and each"
                      " half carries the same number of marks, so which"
                      " way round it goes is yours to say."))
       (setq pick (pm:askpt "Click a spot the run passes through" T))
       (cond
         ((eq pick 'PM-BACK) (setq stage 6))
         (t
          (setq loc (pm:locate en segs (pm:2d (trans pick 1 0))))
          (if (null loc)
            (princ (strcat "\nThe perimeter cannot be read there - click"
                           " nearer the wall, on the side the run runs."))
            (setq way   (pm:far-side-p (caddr loc) s0 s1 tot)
                  stage 8)))))

      ;; --- 8. which dimension style, the question PERPPTS and CPERPPTS
      ;;        ask in the same words.  The run is worked out FIRST, so a
      ;;        pair of ends with nothing between them is reported
      ;;        instead of being asked a question it would throw away ---
      ((= stage 8)
       (setq run  (pm:span (append (list m0 m1) marks) s0 s1 closed tot way)
             pts  (pm:dedupe (mapcar 'pm:m-offs run))
             miss (pm:left-out marks run))
       (cond
         ((< (length pts) 2)
          (princ (strcat "\nThose two ends enclose fewer than two marks,"
                         " so there is no polyline to draw - nothing was"
                         " erased."))
          (setq done T))
         (t
          (setq ans (pm:askkw (strcat "Dimension style - " pm:*dimstyle-std*
                                      " or " pm:*dimstyle-side* "?")
                              "STandard SIde" "STandard/SIde" "STandard" T))
          (cond
            ((eq ans 'PM-BACK) (setq stage (if wayasked 7 6)))
            (t (setq sty   (if (= ans "SIde") pm:*dimstyle-side*
                             pm:*dimstyle-std*)
                     stage 9))))))

      ;; --- 9. draw it ------------------------------------------------
      ((= stage 9)
       (pm:pline pts ed)
       (setq npts (length pts))
       ;; --- the circles go, the lines become dimensions ---------------
       (foreach m marks
         (pm:erase (pm:m-circle m))
         (pm:erase (pm:m-line m)))
       (setq ndims (pm:dimension marks sty))
       ;; a measurement left off the polyline is SAID, never dropped
       ;; quietly: it is still marked and still dimensioned, and the
       ;; drafter is the one who decides whether that is what they meant
       (if miss
         (princ (strcat "\n" (pm:andjoin miss T)
                        (if (= 1 (length miss)) " sits" " sit")
                        " outside the run - still dimensioned, but not"
                        " joined.")))
       (princ (strcat "\nDone: a " (itoa npts)
                      "-point polyline on layer \""
                      (cdr (assoc 8 ed)) "\", "
                      (itoa (length marks))
                      " circle(s) erased and " (itoa ndims)
                      " dimension(s) on layer \"" pm:*dimlayer*
                      "\" in \"" sty "\"."))
       (setq done T))))

  ;; only when pm:dimension moved it: a run answered No never touched the
  ;; style, and restoring it to itself is a command line nobody asked for
  (if (and odim (/= odim (getvar "DIMSTYLE")) (tblsearch "DIMSTYLE" odim))
    (command "_.-DIMSTYLE" "_Restore" odim))
  (if undo-open (setq undo-open (pm:undoend)))
  (pm:sysrestore)
  (if lzd:end (lzd:end "PERPMARK"))
  (princ))

(if (not *calofin-quiet*)
  (princ (strcat "\nPERPMARK " *perpmark-version*
                 " loaded.  Type PERPMARK to run.")))
(princ)
