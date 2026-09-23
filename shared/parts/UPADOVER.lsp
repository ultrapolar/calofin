;;; ======================================================================
;;; UPADOVER.lsp  --  pads laid end to end along the perimeter, from one
;;;                   point round to another
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  UPADOVER     pad the perimeter from one point to another
;;;            UPADOVERVER  print the loaded version
;;; ======================================================================
;;;
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;
;;; What it is for
;;;   PADDLE reads the perimeter and pads the FEATURES it finds -- an
;;;   inside corner, a tight concave arc -- and leaves the wall between
;;;   them bare, because that is where a pad earns its place.  Some
;;;   stretches are not like that: from this point round to that one the
;;;   wall is carried wholesale, and what the drafter wants is the whole
;;;   stretch under pads, laid end to end, with nothing missed and
;;;   nothing doubled.
;;;
;;;   That is this command.  Click the perimeter, name the two points the
;;;   stretch runs between -- click them, or type their numbers the way
;;;   ABHD and PERPMARK take them -- and the run comes back covered.
;;;
;;; Workflow
;;;   1. Click the pool perimeter.  A polyline (arc segments included), a
;;;      line, an arc, a circle -- and anything else AutoCAD can measure
;;;      along, which is read through vlax-curve-* instead.
;;;   2. Where the pads start, and where they end.  Either end is a
;;;      click anywhere on the wall OR a survey point's number: "17",
;;;      "Pt.17", "pt 17", "#17" and "017" all name the same point, and a
;;;      click landing within upad:*snap* of one IS that point.  A pick
;;;      that sits off the wall is projected onto it, and the run says
;;;      how far it had to come.
;;;   3. Which way round -- only when it is a real question.  See below.
;;;
;;; Which way round, and when it is asked
;;;   Two ends cut a closed perimeter into two stretches and the run is
;;;   one of them.  The SHORTER one is what somebody means by "from here
;;;   to there" almost every time, so that is what is taken, and the
;;;   report names both lengths so a wrong guess is visible rather than
;;;   silent.
;;;
;;;   Almost every time is not every time: on a long thin pool the two
;;;   ways round come out near enough the same, and then the shorter one
;;;   is a coin toss wearing a decision's clothes.  So when the two are
;;;   within upad:*evenpct* of each other the question is put -- one
;;;   click on a spot the run passes through, which is the same answer
;;;   PERPMARK asks for in the same words when its own marks cannot
;;;   settle the direction.  Clicking is the whole of it: the stretch
;;;   carrying the click is the stretch that gets the pads.
;;;
;;;   An OPEN perimeter has one stretch between any two points, so it is
;;;   never asked.
;;;
;;; How the pads are laid
;;;   A pad goes down wherever the run comes out from under the pads
;;;   already there, and it goes down ONE PAD ACROSS from the pad it
;;;   came out of, along the axis it came out through.  Two pads offset
;;;   by exactly their own width on one axis meet on that line and
;;;   cannot lie over each other whatever the other axis does -- so the
;;;   other axis is left free, and FOLLOWS THE WALL.
;;;
;;;   That freedom is the whole of it.  The first version laid the pads
;;;   on a fixed grid, which is simple to prove and expensive to build:
;;;   the pads stair-step whatever the wall is doing and sit up to half
;;;   a pad off it.  On the drafter's own comparison drawing the same
;;;   run took 18 pads that way, 14 laid by hand, and 12 this way --
;;;   each of them within about three inches of the wall.
;;;
;;;   How far one pad reaches is measured the same way it is laid: the
;;;   run is followed from where it came out for as long as it stays
;;;   inside the new pad's strip AND the band it sweeps across that
;;;   strip still fits inside one pad.  The pad is then centred on that
;;;   band -- held so it covers the point the run crossed the seam at,
;;;   which is what keeps the seam closed, and so it shares at least
;;;   upad:*mincontact* of an edge with its neighbour rather than
;;;   touching at a corner.  What it actually covers is then walked
;;;   again rather than assumed, so a pad pulled off the middle of its
;;;   band by those two holds cannot leave a tail behind it.
;;;
;;;   The ends are carried past, not stopped at: the first pad is
;;;   centred ON the start point, so the cover begins half a pad before
;;;   it, and the last pad runs past the far end rather than stopping on
;;;   it.  A pad past the point is concrete nobody needed; a wall short
;;;   of one is the thing the run exists to prevent, so that is the
;;;   direction to err in.
;;;
;;;   One thing can stop it, and it is reported rather than papered
;;;   over: a run that comes back within a pad's width of itself -- a
;;;   slot narrower than a pad, or a whole loop closing on its own first
;;;   pad -- has stretches where every pad that would cover them lies
;;;   over one already down.  Those are left bare, measured, and named.
;;;
;;; What it reports
;;;   How many pads, on which layer, how much perimeter they cover and
;;;   between which two points; which way round it went and what the
;;;   other way would have been; and either that the wall is under pads
;;;   end to end or exactly how much of it is not.  A pick that had to
;;;   be projected onto the wall is named with the distance it moved.
;;;
;;; Robustness
;;;   * The whole run is one UNDO group: a single U reverses all of it.
;;;   * Esc or an error at any prompt restores every system variable the
;;;     command changed and closes the UNDO group.
;;;   * A number nothing carries, a number two points share, a perimeter
;;;     with no length, a perimeter this file cannot measure along and a
;;;     second pick on the first one's spot all re-prompt where they
;;;     stand instead of guessing.
;;;   * Geometry is worked in WCS and converted at the edges, so the
;;;     command behaves under a rotated or shifted UCS.
;;;
;;; License: GPL-3.0-or-later
;;; ----------------------------------------------------------------------

(vl-load-com)

;; Version banner: tools/release_lisp.py reads it to stamp the dated
;; REV twin in releases/ (vN.M -> _MMDDYY_REVNM).
(setq *upadover-version* "v1.4")

;;; ----------------------------------------------------------------------
;;;  Tunables
;;; ----------------------------------------------------------------------

;; Block inserted at every pad spot, and the edge of that pad in drawing
;; units.  The two go together: the size is the pitch of the whole grid,
;; so a block that is not that size leaves gaps between pads or laps
;; them.  upad:*blkfile* ships Pad36x36 and Pad24x24.
(setq upad:*blkname* "Pad36x36")
(setq upad:*padsize* 36.0)

;; The dwg the block definitions are imported from when the drawing does
;; not already hold them.  Looked up with findfile, so put its folder on
;; the AutoCAD support path or drop the dwg beside the drawing; if it
;; cannot be found a plain square block of the right size is made.
(setq upad:*blkfile* "24inpad.dwg")

;; Layer the pads land on -- PADDLE's, so a drawing padded by both has
;; them in one place -- and the colour it is CREATED with.  An existing
;; layer keeps its own colour, and is thawed, unlocked and switched on
;; so the run is visible.
(setq upad:*layer* "PADS")
(setq upad:*layercolor* 7)

;; How near the two ways round a closed perimeter have to be before the
;; shorter one stops being an answer and the question is put instead.
;; 0.70 is "within 30% of each other".  Raise it to be asked less often
;; and guessed at more; 1.0 asks every time there is a choice.
(setq upad:*evenpct* 0.70)

;; How finely the run is walked, in samples per pad width.  It is the
;; resolution the cover is worked out at: every cell a sample lands in
;; gets a pad, so raising it can only ever find another cell the wall
;; clips, at the price of a longer walk.  Below about 8 a run could
;; cross a corner of a cell between two samples and miss it.
(setq upad:*samples* 48)

;; How much of their shared edge two neighbouring pads have to have in
;; common.  Every pad is laid exactly one pad across from the one the run
;; came out of, so the two always meet on that line; this is how much of
;; the line they must actually share.  0 lets them meet at a CORNER,
;; which is what a run at exactly 45 degrees does if nothing stops it --
;; a joint with no width, and a break in everything but topology.  6"
;; costs nothing on any shape tried; raising it holds neighbours closer
;; together and buys the odd extra pad on a diagonal.
(setq upad:*mincontact* 6.0)

;; A click within this of a survey point picks that point rather than
;; the place it landed.  12.0 is what PERPMARK, BPCALLOUT and ABFIND
;; snap at, so a drafter's aim carries between them.  A number typed at
;; the same prompt never uses it -- a name is exact.
(setq upad:*snap* 12.0)

;; How far off the perimeter a pick may sit before the run says where it
;; landed.  A quarter inch is drafting noise; anything more is worth a
;; line, because a pick projected across the pool is how the wrong
;; stretch gets padded quietly.
(setq upad:*onwall* 0.25)

;; Two stations closer than this along the wall are the same place: it
;; is what refuses a run whose two ends are one point.
(setq upad:*fuzz* 1e-6)

;; What counts as a survey point.  The classifier is the one PERPMARK,
;; BPCALLOUT, CDCALLOUT, ABFIND and LHD share: change it in all of them
;; or the tools disagree about what the drawing holds.
(setq upad:*point-block* "ab_pt")   ; block name whose INSERTs mark
                                    ; points wherever they sit
(setq upad:*point-layer* "POINTS")  ; layer whose POINTs and INSERTs are
                                    ; always points, whatever block
(setq upad:*pt-tag* "number")       ; attribute tag on the point block
                                    ; naming the point.  A block without
                                    ; it lends its first attribute that
                                    ; reads as a number instead
(setq upad:*unknown* "?")           ; what a point with no readable
                                    ; number is called.  It can still be
                                    ; clicked; only a number can be typed
(setq upad:*pt-prefix* "Pt.")       ; how a point is named in the prompts
                                    ; and the report

;;; ----------------------------------------------------------------------
;;;  Vectors, angles and numbers
;;;  Copied from CALOFIN-LIB.lsp under this file's own prefix, so the
;;;  standalone file loads alone -- see STANDARDS.md section 4.
;;; ----------------------------------------------------------------------

;; A length as inches with the mark, 36.0 -> 36" -- every message that
;; quotes the pad size goes through this, so upad:*padsize* is the only
;; place it is written.
(defun upad:in (n)
  (strcat (rtos n 2 (if (equal n (float (fix n)) 1e-9) 0 2)) "\""))

;; A length along the wall, in feet and inches: a run is quoted the way
;; the drawing dimensions it.
(defun upad:ft (n) (rtos n 4 0))

;;; ----------------------------------------------------------------------
;;;  The perimeter, as segments
;;;
;;;  Read off the entity itself rather than through vlax-curve-*, for the
;;;  same reason PERPMARK does it: the run is a STATION -- how far along
;;;  the wall a point sits -- and the walk that projects a pick onto the
;;;  wall hands the station back as a by-product, where the COM surface
;;;  would be a round trip per sample and the cover takes hundreds.
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
(defun upad:mkseg (p1 p2 b / inc ch r th d cx cy ctr)
  (setq inc (* 4.0 (atan b))
        ch  (distance (cal:2d p1) (cal:2d p2)))
  (if (or (< (abs b) 1e-12)
          (< ch 1e-12)
          (< (abs (sin (/ inc 2.0))) 1e-12))
    (list 'S (cal:2d p1) (cal:2d p2))
    (progn
      (setq r   (abs (/ ch (* 2.0 (sin (/ inc 2.0)))))
            th  (angle (cal:2d p1) (cal:2d p2))
            d   (/ (/ ch 2.0) (cal:tan (/ inc 2.0)))
            cx  (+ (/ (+ (car p1) (car p2)) 2.0)
                   (* d (cos (+ th (/ pi 2.0)))))
            cy  (+ (/ (+ (cadr p1) (cadr p2)) 2.0)
                   (* d (sin (+ th (/ pi 2.0)))))
            ctr (list cx cy))
      (list 'A ctr r (angle ctr (cal:2d p1)) inc))))

;; The vertices of an LWPOLYLINE as (point bulge), in order.  entget
;; hands the groups back in order, so a 42 belongs to the 10 in front of
;; it; a vertex with no 42 carries no bulge.
(defun upad:lwverts (ed / vs g)
  (setq vs '())
  (foreach g ed
    (cond
      ((= 10 (car g)) (setq vs (cons (list (cal:2d (cdr g)) 0.0) vs)))
      ((and (= 42 (car g)) vs)
       (setq vs (cons (list (car (car vs)) (cdr g)) (cdr vs))))))
  (reverse vs))

;; The entity as segments, or nil when this file cannot read it and the
;; COM surface has to.
(defun upad:segs (en / ed typ vs closed n i out a0 a1 sw v1 v2)
  (setq ed  (entget en)
        typ (cdr (assoc 0 ed))
        out '())
  (cond
    ((= typ "LINE")
     (list (list 'S (cal:2d (cdr (assoc 10 ed)))
                 (cal:2d (cdr (assoc 11 ed))))))
    ((= typ "ARC")
     (setq a0 (cdr (assoc 50 ed))
           a1 (cdr (assoc 51 ed))
           sw (cal:angnorm (- a1 a0)))
     (if (< sw 1e-12) (setq sw (+ pi pi)))
     (list (list 'A (cal:2d (cdr (assoc 10 ed))) (cdr (assoc 40 ed)) a0 sw)))
    ((= typ "CIRCLE")
     (list (list 'A (cal:2d (cdr (assoc 10 ed))) (cdr (assoc 40 ed))
                 0.0 (+ pi pi))))
    ((= typ "LWPOLYLINE")
     (setq vs     (upad:lwverts ed)
           n      (length vs)
           closed (= 1 (logand 1 (cond ((cdr (assoc 70 ed))) (0))))
           i      0)
     (if (< n 2)
       nil
       (progn
         (while (< i (if closed n (1- n)))
           (setq v1  (nth i vs)
                 v2  (nth (rem (1+ i) n) vs)
                 out (cons (upad:mkseg (car v1) (car v2) (cadr v1)) out)
                 i   (1+ i)))
         (reverse out))))
    (t nil)))

(defun upad:seg-len (s)
  (if (eq (car s) 'S)
    (distance (cadr s) (caddr s))
    (* (caddr s) (abs (nth 4 s)))))

(defun upad:seg-start (s / ctr)
  (if (eq (car s) 'S)
    (cadr s)
    (progn
      (setq ctr (cadr s))
      (list (+ (car ctr)  (* (caddr s) (cos (nth 3 s))))
            (+ (cadr ctr) (* (caddr s) (sin (nth 3 s))))))))

(defun upad:seg-end (s / ctr a)
  (if (eq (car s) 'S)
    (caddr s)
    (progn
      (setq ctr (cadr s)
            a   (+ (nth 3 s) (nth 4 s)))
      (list (+ (car ctr)  (* (caddr s) (cos a)))
            (+ (cadr ctr) (* (caddr s) (sin a)))))))

;; The point of S closest to P.  A straight segment clamps the
;; projection to its ends; an arc takes the radial point when the
;; direction of P falls inside the sweep and the nearer end when it does
;; not.
(defun upad:seg-closest (s p / a b d l t01 ctr r rel u)
  (setq p (cal:2d p))
  (if (eq (car s) 'S)
    (progn
      (setq a (cadr s)
            b (caddr s)
            d (cal:v- b a)
            l (cal:dot d d))
      (if (< l 1e-24)
        a
        (progn
          (setq t01 (/ (cal:dot (cal:v- p a) d) l))
          (cond ((< t01 0.0) (setq t01 0.0))
                ((> t01 1.0) (setq t01 1.0)))
          (cal:v+ a (cal:v* d t01)))))
    (progn
      (setq ctr (cadr s)
            r   (caddr s)
            u   (cal:unit (cal:v- p ctr)))
      (if (null u)
        (upad:seg-start s)
        (progn
          ;; how far into the sweep the direction of P lies, measured
          ;; the way the sweep runs
          (setq rel (cal:angnorm (* (if (< (nth 4 s) 0.0) -1.0 1.0)
                                     (- (angle ctr p) (nth 3 s)))))
          (if (<= rel (abs (nth 4 s)))
            (cal:v+ ctr (cal:v* u r))
            (if (< (distance p (upad:seg-start s))
                   (distance p (upad:seg-end s)))
              (upad:seg-start s)
              (upad:seg-end s))))))))

;; Arc length from the start of S to Q, a point already on it.
(defun upad:seg-station (s q / ctr rel)
  (if (eq (car s) 'S)
    (distance (cadr s) (cal:2d q))
    (progn
      (setq ctr (cadr s)
            rel (cal:angnorm (* (if (< (nth 4 s) 0.0) -1.0 1.0)
                                 (- (angle ctr q) (nth 3 s)))))
      (if (> rel (abs (nth 4 s)))
        ;; past the far end: the clamp landed on one end or the other
        (if (< (distance (cal:2d q) (upad:seg-start s))
               (distance (cal:2d q) (upad:seg-end s)))
          0.0
          (upad:seg-len s))
        (* (caddr s) rel)))))

;; The point D along S from its start.
(defun upad:seg-at (s d / a b l ctr r ang)
  (if (eq (car s) 'S)
    (progn
      (setq a (cadr s)
            b (caddr s)
            l (distance a b))
      (if (< l 1e-12) a (cal:v+ a (cal:v* (cal:v- b a) (/ d l)))))
    (progn
      (setq ctr (cadr s)
            r   (caddr s)
            ang (+ (nth 3 s) (* (if (< (nth 4 s) 0.0) -1.0 1.0) (/ d r))))
      (list (+ (car ctr)  (* r (cos ang)))
            (+ (cadr ctr) (* r (sin ang)))))))

(defun upad:total (segs / tot s)
  (setq tot 0.0)
  (foreach s segs (setq tot (+ tot (upad:seg-len s))))
  tot)

;; T when the walk closes back on itself -- a circle, a closed polyline,
;; or a shape drawn open but ending where it started.
(defun upad:closed-p (segs)
  (and segs
       (< (distance (upad:seg-start (car segs))
                    (upad:seg-end (last segs)))
          1e-9)))

;; (base station) for the point of SEGS closest to P, all WCS.
(defun upad:project (segs p / acc best bd s q d)
  (setq acc 0.0 best nil bd nil)
  (foreach s segs
    (setq q (upad:seg-closest s p)
          d (distance (cal:2d p) q))
    (if (or (null best) (< d bd))
      (setq best (list q (+ acc (upad:seg-station s q)))
            bd   d))
    (setq acc (+ acc (upad:seg-len s))))
  best)

;; The point of SEGS at station ST, measured from the start of the walk.
(defun upad:at (segs st / acc out l s)
  (setq acc 0.0 out nil)
  (foreach s segs
    (setq l (upad:seg-len s))
    (if (and (null out) (<= st (+ acc l 1e-9)))
      (setq out (upad:seg-at s (max 0.0 (- st acc)))))
    (setq acc (+ acc l)))
  (if out out (upad:seg-end (last segs))))

;;; ----------------------------------------------------------------------
;;;  The perimeter AutoCAD can measure but this file cannot read
;;;
;;;  A SPLINE, an ELLIPSE or an old heavy POLYLINE has no segment list
;;;  here, so the same questions are asked of AutoCAD instead.  Every
;;;  call is caught -- a curve AutoCAD will not answer for comes back nil
;;;  and the pick is re-prompted, never half-measured.
;;; ----------------------------------------------------------------------

(defun upad:comcall (fn args / r)
  (setq r (vl-catch-all-apply fn args))
  (if (vl-catch-all-error-p r) nil r))

(defun upad:project-com (en p / q st)
  (setq q (upad:comcall 'vlax-curve-getClosestPointTo (list en (cal:2d p))))
  (if (null q)
    nil
    (progn
      (setq st (upad:comcall 'vlax-curve-getDistAtPoint (list en q)))
      (if (numberp st) (list (cal:2d q) st)))))

(defun upad:at-com (en st / p)
  (setq p (upad:comcall 'vlax-curve-getPointAtDist (list en st)))
  (if p (cal:2d p)))

;; Either reader, whichever this perimeter answers to.
(defun upad:locate (en segs p)
  (if segs (upad:project segs p) (upad:project-com en p)))

(defun upad:point-at (en segs st)
  (if segs (upad:at segs st) (upad:at-com en st)))

(defun upad:runlen (en segs / prm r)
  (if segs
    (upad:total segs)
    (progn
      (setq prm (upad:comcall 'vlax-curve-getEndParam (list en))
            r   (if prm (upad:comcall 'vlax-curve-getDistAtParam
                                      (list en prm))))
      (if (numberp r) r 0.0))))

(defun upad:isclosed (en segs)
  (if segs
    (upad:closed-p segs)
    (if (upad:comcall 'vlax-curve-isClosed (list en)) T)))

;;; ----------------------------------------------------------------------
;;;  The survey points
;;;
;;;  A stretch of wall is named by the shots either end of it, so a run
;;;  end is a survey point wherever the drafter has one.  The classifier
;;;  is the family's: an ab_pt INSERT wherever it sits, any other INSERT
;;;  on the POINTS layer, and a plain POINT on that layer.
;;;
;;;  A point with no readable number is carried as "?" rather than
;;;  dropped: it can be clicked like any other, it just cannot be typed.
;;; ----------------------------------------------------------------------

(defun upad:cd-pt (c) (car c))       ; (x y)
(defun upad:cd-nm (c) (cadr c))      ; "17", or upad:*unknown*

;; "Pt.17", the way the prompts and the report name a point.
(defun upad:ptname (nm) (strcat upad:*pt-prefix* nm))

;; The space the drafter is drawing in: model space from the Model tab
;; and from inside a layout's viewport, the layout's paper only when it
;; is the paper that is active -- PADDLE's pair, under this prefix.
;; The sweep below read every space at once, so a sheet whose title
;; block carries a numbered point turned a typed number into "2 points
;; are numbered" with only one of them anywhere near the pool; and the
;; pads went into the ACTIVE LAYOUT's block, which from inside a
;; viewport is the sheet's paper, not the model space the perimeter
;; was picked in.  The sweep and the inserts both go through these two,
;; so they cannot disagree.
(defun upad:tab ()
  (if (= 1 (getvar "CVPORT")) (getvar "CTAB") "Model"))

(defun upad:space (doc)
  (if (and (= 0 (getvar "TILEMODE")) (/= 1 (getvar "CVPORT")))
      (vla-get-ModelSpace doc)
      (vla-get-Block (vla-get-ActiveLayout doc))))

;; Every survey point in the space being drawn in, as (position name).
(defun upad:collect-points ( / ss i en ed typ p nm out)
  (setq out nil
        ss  (ssget "_X" (list '(0 . "INSERT,POINT")
                              (cons 410 (upad:tab)))))
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
                      (strcase upad:*point-block*))
                   (= (strcase (cdr (assoc 8 ed)))
                      (strcase upad:*point-layer*)))
             (progn
               (setq nm (cal:block-number en upad:*pt-tag*))
               (setq out (cons (list (list (car p) (cadr p))
                                     (if (and nm (/= nm "")) nm upad:*unknown*))
                               out)))))
          ((= typ "POINT")
           (if (= (strcase (cdr (assoc 8 ed)))
                  (strcase upad:*point-layer*))
             (setq out (cons (list (list (car p) (cadr p)) upad:*unknown*)
                             out)))))
        (setq i (1+ i)))))
  (reverse out))

;;; ----------------------------------------------------------------------
;;;  Ask helpers
;;;  Under this file's own prefix, so the standalone file loads alone --
;;;  see STANDARDS.md section 4.  Back sentinel: UPAD-BACK.
;;; ----------------------------------------------------------------------

;; A PLACE, in the current UCS -- the way-round click, and nothing else
;; in this command.  Always required: Enter re-asks.  Returns the point
;; or UPAD-BACK.
(defun upad:askpt (msg back / v)
  (if back (initget 1 "Back Undo") (initget 1))
  (setq v (getpoint (strcat "\n" msg (if back " [Back]" "") ": ")))
  (if lzd:ask (lzd:ask msg v) v)
  (if (and (= (type v) 'STR) (member v '("Back" "Undo"))) 'UPAD-BACK v))

;; An end of the run: a survey point, or any place on the wall.  One
;; prompt takes both -- (initget 128) is arbitrary input, which hands
;; typed text back from getpoint as the string it is where a click comes
;; back as the point it is -- so the number on the sheet and a click on
;; the wall are one question.
;;
;; This is NOT cal:askpoint with a new prefix, and the grouped twin does
;; not swap it for one: the library's question is about a survey POINT
;; and re-asks a click that lands on nothing, where a stretch of wall is
;; a stretch of wall whether anybody shot its ends or not.  A click within upad:*snap* of a survey
;; point IS that point and is named like one; a click anywhere else is
;; the place it landed.  The misses are re-asked HERE rather than
;; unwinding the caller's chain: a number nothing carries is a typo, not
;; an answer, and the question it belongs to is this one.
;;
;; WHOLE offers the Whole keyword -- all of the curve rather than a
;; stretch of it -- and is answered UPAD-WHOLE.  The bracket is built
;; from the keyword list rather than written a second time, so a click
;; on a bracketed word always sends a word initget accepts (STANDARDS
;; section 1).
;;
;; Returns (position name), name nil for a place, UPAD-WHOLE, or
;; UPAD-BACK.
(defun upad:askpoint (msg whole back cands / v out done dupes hit kws)
  (setq kws  (cond ((and whole back) "Whole Back")
                   (whole            "Whole")
                   (back             "Back")
                   (t                ""))
        done nil
        out  nil)
  (while (not done)
    ;; Undo rides along as a hidden alias for Back, unlisted
    (if (= kws "")
      (initget 129)
      (initget 129 (strcat kws (if back " Undo" ""))))
    (setq v (getpoint (strcat "\n" msg
                              (if (= kws "")
                                ""
                                (strcat " ["
                                        (vl-string-translate " " "/" kws)
                                        "]"))
                              ": ")))
    (if lzd:ask (lzd:ask msg v) v)
    (cond
      ((null v)
       (princ (strcat "\nA place is required - click the wall, or type a"
                      " survey point's number.")))
      ;; each keyword counts only where this prompt OFFERS it: initget
      ;; 128 lets any typed word through, and a "Whole" typed at the
      ;; end prompt (which has no Whole) came back UPAD-WHOLE to a
      ;; caller that took it for a point and died on it
      ((and back (= (type v) 'STR) (member v '("Back" "Undo")))
       (setq out 'UPAD-BACK done T))
      ((and whole (= (type v) 'STR) (= v "Whole"))
       (setq out 'UPAD-WHOLE done T))
      ((= (type v) 'STR)
       (setq dupes (cal:cand-matches v cands))
       (cond
         ((null dupes)
          (princ (strcat "\nNo survey point is numbered \""
                         (cal:as-number v)
                         "\" - try again, or click the place itself.")))
         ((> (length dupes) 1)
          (princ (strcat "\n" (itoa (length dupes)) " points are numbered \""
                         (cal:as-number v)
                         "\" - click the one you mean.")))
         (t (setq out (list (upad:cd-pt (car dupes)) (upad:cd-nm (car dupes)))
                  done T))))
      (t
       (setq v   (cal:2d (trans v 1 0))
             hit (cal:cand-nearest v cands upad:*snap*))
       (setq out  (if hit
                    (list (upad:cd-pt hit) (upad:cd-nm hit))
                    (list v nil))
             done T))))
  out)

;;; ----------------------------------------------------------------------
;;;  System variables and undo
;;; ----------------------------------------------------------------------


;; OSMODE is deliberately NOT in this list.  UPADOVER never changes it --
;; the pads go in through ActiveX, not through a (command ...) a running
;; snap could pull off its point -- and a list is a promise to WRITE the
;; value back: the run would put its opening snapshot back over any snap
;; the drafter ticked on while it was up.  Borrow only what you move.
(defun upad:sysvars () '("CMDECHO"))

;;; ----------------------------------------------------------------------
;;;  Which way round
;;; ----------------------------------------------------------------------

(defun upad:wrap (d tot)
  (if (< tot 1e-12)
    0.0
    (progn
      (while (< d 0.0) (setq d (+ d tot)))
      (while (>= d tot) (setq d (- d tot)))
      d)))

;; T when station ST sits on the FAR stretch -- the one that leaves s0
;; going backwards.  It is what the way-round click reads.
(defun upad:far-side-p (st s0 s1 tot)
  (> (upad:wrap (- st s0) tot) (+ (upad:wrap (- s1 s0) tot) upad:*fuzz*)))

;; T when two lengths are near enough the same that calling one of them
;; shorter is a coin toss: the smaller is at least upad:*evenpct* of the
;; larger.  A zero-length stretch is never ambiguous.
(defun upad:even-p (a b)
  (and (> (max a b) 1e-9)
       (>= (/ (min a b) (max a b)) upad:*evenpct*)))

;;; ----------------------------------------------------------------------
;;;  The cover
;;;
;;;  A pad goes down wherever the run comes out from under the pads
;;;  already there, and it goes down ONE PAD ACROSS from the pad it came
;;;  out of, along the axis it came out through.  Two pads offset by
;;;  exactly their own width on one axis meet on that line and cannot
;;;  lap each other whatever the other axis does -- so the other axis is
;;;  left free, and follows the WALL.
;;;
;;;  That freedom is the whole of it.  Pads laid on a fixed grid instead
;;;  have to stair-step whatever the wall is doing, and pay for it: on
;;;  the drafter's own comparison a run took 18 pads on a grid and 14 by
;;;  hand, and this takes 12 -- each of them sitting on the wall rather
;;;  than up to half a pad off it.
;;;
;;;  The stretch a new pad covers is decided the same way it is laid:
;;;  the run is followed from where it came out for as long as it stays
;;;  inside the new pad's strip AND the band it sweeps across that strip
;;;  still fits inside one pad.  The pad is then centred on that band,
;;;  held so it still covers the point the run came out at -- which is
;;;  what keeps the seam between the two pads closed -- and so it shares
;;;  a real edge with its neighbour rather than touching at a corner.
;;; ----------------------------------------------------------------------

;; The run sampled end to end: the point of the perimeter at station S0
;; and every STEP along it for LEN, the far end included exactly.  SGN is
;; +1 forward along the wall, -1 back; a closed wall wraps past its own
;; seam, an open one cannot and is clamped instead.
(defun upad:walk (en segs tot closed s0 sgn len step / out n k st)
  (setq n (fix (/ len step)) k 0 out nil)
  (while (<= k n)
    (setq st  (+ s0 (* sgn (* k step)))
          st  (if closed (upad:wrap st tot) (max 0.0 (min tot st)))
          out (cons (upad:point-at en segs st) out)
          k   (1+ k)))
  (if (> (- len (* n step)) 1e-9)
    (progn
      (setq st (+ s0 (* sgn len))
            st (if closed (upad:wrap st tot) (max 0.0 (min tot st))))
      (setq out (cons (upad:point-at en segs st) out))))
  (reverse out))

;; The pad of OUT covering P, or nil.  A pad reaches HALF either side of
;; its centre on both axes, so this is a Chebyshev test.
(defun upad:covered-by (p out half / hit c)
  (foreach c out
    (if (and (null hit)
             (<= (abs (- (car p) (car c))) (+ half 1e-9))
             (<= (abs (- (cadr p) (cadr c))) (+ half 1e-9)))
      (setq hit c)))
  hit)

;; T when a pad centred on C would lap one already down.
(defun upad:laps-p (c out pitch / hit q)
  (foreach q out
    (if (and (null hit)
             (< (max (abs (- (car c) (car q))) (abs (- (cadr c) (cadr q))))
                (- pitch 1e-6)))
      (setq hit T)))
  hit)

;; How many of PTS no pad covers -- the cover checked against the run it
;; was laid for, rather than trusted.
(defun upad:bare (pts out half / n p)
  (setq n 0)
  (foreach p pts
    (if (not (upad:covered-by p out half)) (setq n (1+ n))))
  n)

;; C slid along its free axis to the nearest spot inside [W0 W1] that
;; laps nothing.  The spots worth trying are the ones exactly one pad
;; clear of a pad already down; nil when none of them is in the window,
;; which is a stretch of wall no pad can take without lapping one.
(defun upad:clear-of (c out pitch ax w0 w1 / fx best bd q v cand)
  (setq fx (- 1 ax))
  (foreach q out
    (if (< (abs (- (nth ax c) (nth ax q))) (- pitch 1e-6))
      (foreach v (list (- (nth fx q) pitch) (+ (nth fx q) pitch))
        (if (and (>= v (- w0 1e-9)) (<= v (+ w1 1e-9)))
          (progn
            (setq cand (if (= ax 0)
                         (list (car c) v)
                         (list v (cadr c))))
            (if (and (not (upad:laps-p cand out pitch))
                     (or (null best) (< (abs (- v (nth fx c))) bd)))
              (setq best cand
                    bd   (abs (- v (nth fx c))))))))))
  best)

;; The pads the run needs, in the order it walks them.  PTS is the run
;; sampled end to end and its first point is where the first pad is
;; centred -- on the start, so the cover begins half a pad before it.
;; MINC is how much of their shared edge two neighbours must have in
;; common.
(defun upad:cover (pts pitch minc / half out last prev rest look e ax fx
                        a b lo hi done moved p w0 w1 cand d cross)
  (setq half (/ pitch 2.0)
        out  (list (car pts))
        last (car pts)
        rest (cdr pts))
  (while rest
    ;; run on while the wall is still under a pad that is already down --
    ;; a wall that doubles back within a pad's width of itself is covered
    ;; by the pads of its first pass, and laying a second row over them
    ;; is exactly what must not happen
    (setq prev (car out))
    (while (and rest (setq p (upad:covered-by (car rest) out half)))
      (setq last p
            prev (car rest)
            rest (cdr rest)))
    (if rest
      (progn
        (setq e     (car rest)
              ;; the side it came out through
              ax    (if (>= (abs (- (car e) (car last)))
                            (abs (- (cadr e) (cadr last))))
                      0 1)
              fx    (- 1 ax)
              a     (+ (nth ax last)
                       (if (> (nth ax e) (nth ax last)) pitch (- pitch)))
              lo    (nth fx e)
              hi    lo
              look  rest
              done  nil
              moved nil)
        ;; how far one pad can follow the run from here
        (while (and look (not done))
          (setq p (car look))
          (if (or (> (abs (- (nth ax p) a)) (+ half 1e-9))
                  (> (- (max hi (nth fx p)) (min lo (nth fx p))) pitch))
            (setq done T)
            (setq lo    (min lo (nth fx p))
                  hi    (max hi (nth fx p))
                  look  (cdr look)
                  moved T)))
        ;; WHERE it came out, not just the first sample after it did:
        ;; the run crosses the line the two pads meet on somewhere
        ;; between the last sample under the old pad and the first one
        ;; out from under it, and the new pad has to cover that crossing
        ;; or the seam leaks the fraction of an inch between two samples
        (setq d     (- (nth ax e) (nth ax prev))
              cross (if (< (abs d) 1e-9)
                      (nth fx e)
                      (+ (nth fx prev)
                         (* (- (nth fx e) (nth fx prev))
                            (/ (- (+ (nth ax last)
                                     (if (> (nth ax e) (nth ax last))
                                       half (- half)))
                                  (nth ax prev))
                               d)))))
        ;; the free coordinate: the middle of the band the run swept,
        ;; held so the pad covers both the crossing and the sample after
        ;; it, and so the two pads share an edge rather than a corner
        (setq w0   (max (- (max (nth fx e) cross) half)
                        (- (nth fx last) (- pitch minc)))
              w1   (min (+ (min (nth fx e) cross) half)
                        (+ (nth fx last) (- pitch minc)))
              b    (max w0 (min w1 (/ (+ lo hi) 2.0)))
              cand (if (= ax 0) (list a b) (list b a)))
        (if (upad:laps-p cand out pitch)
          (setq cand (upad:clear-of cand out pitch ax w0 w1)))
        (if cand
          ;; REST is left where it is: the loop above walks it forward
          ;; over whatever the new pad actually covers, which is not
          ;; always the whole band it was measured against -- holding the
          ;; pad to the seam and to its neighbour can pull it off that
          ;; band's middle, and a walk that trusted the measurement
          ;; instead would step over the tail it no longer covers
          (setq out  (cons cand out)
                last cand)
          ;; nothing in the window is clear: this stretch takes no pad
          ;; without lapping one already down, so it is left, counted and
          ;; reported rather than covered twice
          (setq rest (if moved look (cdr rest)))))))
  (reverse out))

;;; ----------------------------------------------------------------------
;;;  Layers, blocks and the pads themselves
;;;  The pad machinery is PADDLE's, ported under this file's own prefix.
;;; ----------------------------------------------------------------------

;; Last-resort pad: a plain size x size square block, base at centre.
(defun upad:make-fallback-block (name size / h)
  (setq h (/ size 2.0))
  (entmake (list '(0 . "BLOCK") (cons 2 name)
                 '(10 0.0 0.0 0.0) '(70 . 0)))
  (entmake (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") '(8 . "0")
                 '(100 . "AcDbPolyline") '(90 . 4) '(70 . 1)
                 (list 10 (- h) (- h)) (list 10 h (- h))
                 (list 10 h h) (list 10 (- h) h)))
  (entmake '((0 . "ENDBLK")))
  (princ (strcat "\nUPADOVER: block \"" name "\" not found; created a plain "
                 (rtos size 2 0) "x" (rtos size 2 0) " square block instead."))
  (tblsearch "BLOCK" name))

;; Make sure block NAME (a SIZE-inch pad) is defined in the drawing.
(defun upad:ensure-block (doc name size / path oldcmd oldatt tmpname)
  (cond
    ((tblsearch "BLOCK" name) T)
    ;; pull the definitions in from the pad dwg if it can be found --
    ;; inserting the file (under a throwaway name, then cancelling)
    ;; imports every block definition it contains
    ((setq path (findfile upad:*blkfile*))
     (setq oldcmd (getvar "CMDECHO") oldatt (getvar "ATTREQ")
           tmpname "UPADOVER-TEMP-IMPORT")
     (setvar "CMDECHO" 0) (setvar "ATTREQ" 0)
     ;; the restore below must run even if the insert throws: oldcmd and
     ;; oldatt are locals of THIS helper, so c:UPADOVER's *error* handler
     ;; cannot put them back and the drafter would be left with no
     ;; command echo and no attribute prompts
     (vl-catch-all-apply
       '(lambda ()
          (command "_.-INSERT" (strcat tmpname "=" path))
          (command)) '())   ; cancel the insert -- the definitions stay
     (setvar "CMDECHO" oldcmd) (setvar "ATTREQ" oldatt)
     (vl-catch-all-apply ; drop the unused throwaway definition
       '(lambda () (vla-Delete (vla-Item (vla-get-Blocks doc) tmpname))) '())
     (if (tblsearch "BLOCK" name)
       T
       (upad:make-fallback-block name size)))
    (t (upad:make-fallback-block name size))))

;; Offset from the block's insertion point to the centre of its extents
;; (measured at 0 rotation), so pads land centred no matter where the
;; block's base point was drawn.
(defun upad:block-delta (space name / tmp mn mx d)
  (setq tmp (vla-InsertBlock space (vlax-3d-point 0.0 0.0 0.0)
                             name 1.0 1.0 1.0 0.0))
  (vla-GetBoundingBox tmp 'mn 'mx)
  (setq mn (vlax-safearray->list mn)
        mx (vlax-safearray->list mx)
        d  (list (/ (+ (car mn) (car mx)) 2.0)
                 (/ (+ (cadr mn) (cadr mx)) 2.0)))
  (vla-Delete tmp)
  d)

;; One pad, its extents centred on CTR.  Pads are square to the drawing:
;; a rotated one could not share an edge with the next, and edges are
;; what hold the cover together.
(defun upad:insert-pad (space name ctr delta / ip obj)
  (setq ip  (cal:v- ctr delta)
        obj (vla-InsertBlock space
              (vlax-3d-point (car ip) (cadr ip) 0.0)
              name 1.0 1.0 1.0 0.0))
  (vla-put-Layer obj upad:*layer*)
  obj)

;;; ----------------------------------------------------------------------
;;;  Naming the ends
;;; ----------------------------------------------------------------------

;; What the report calls a run end: its point number where it has one,
;; and the place it was clicked where it does not.
(defun upad:endname (e where)
  (if (and (cadr e) (/= (cadr e) upad:*unknown*))
    (upad:ptname (cadr e))
    where))

;; Says where a pick landed when it did not land on the wall.  A pick
;; projected across the pool is how the wrong stretch gets padded
;; quietly, so the distance is named rather than absorbed.
(defun upad:say-landed (e base what / d)
  (setq d (distance (upad:cd-pt e) base))
  ;; inches rather than feet and inches: this is a drafting slip being
  ;; measured, not a length of wall, and a quarter of an inch reads as
  ;; one at that scale where 0'-0" would not
  (if (> d upad:*onwall*)
    (princ (strcat "\nUPADOVER: the " what " sits " (upad:in d)
                   " off the wall - taken on the wall under it."))))

;;; ----------------------------------------------------------------------
;;;  Commands
;;; ----------------------------------------------------------------------

;; ahead of the command on purpose: the structural test scans from
;; c:UPADOVER to end-of-file for leaked variables, and a defun name there
;; would read as one
(defun c:UPADOVERVER ()
  (princ (strcat "\nUPADOVER " *upadover-version*))
  (princ))

(defun c:UPADOVER (/ *error* undo-open doc space sel en ed segs tot closed
                     cands stage done pick e0 e1 loc base0 base1 s0 s1
                     lf lb sgn runlen otherlen asked pts pads delta
                     nbare step blkname padsize e gap whole)

  (defun *error* (msg)
    ;; user settings come back FIRST so nothing below can skip them
    (cal:sysrestore)
    ;; command-s, never plain command: 2015+ engines reject (command)
    ;; inside *error* unless the error mode was pushed beforehand
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (setq undo-open nil)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nUPADOVER error: " msg)))
    (if lzd:report (lzd:report "UPADOVER" *upadover-version* msg))
    (princ))

  (if lzd:begin (lzd:begin "UPADOVER" *upadover-version*))
  (cal:syssave (upad:sysvars))
  (setvar "CMDECHO" 0)
  (setq undo-open (cal:undobegin)
        doc       (vla-get-ActiveDocument (vlax-get-acad-object))
        space     (upad:space doc)
        padsize   upad:*padsize*
        blkname   upad:*blkname*
        stage     1
        done      nil)

  (princ (strcat "\nUPADOVER " *upadover-version* " - " (upad:in padsize)
                 " pads end to end, from one point round to another."))

  (while (not done)
    (cond

      ;; --- 1. the perimeter the run follows ---------------------------
      ((= stage 1)
       (setq sel (entsel "\nSelect the perimeter, or the line or polyline to pad: "))
       (if lzd:ask (lzd:ask "\nSelect the perimeter, or the line or polyline to pad: " sel) sel)
       (if lzd:watch (lzd:watch sel) sel)
       (cond
         ((null sel)
          (princ "\nNothing selected - try again, or press Esc to quit."))
         (t
          (setq en   (car sel)
                ed   (entget en)
                segs (upad:segs en)
                tot  (upad:runlen en segs))
          (cond
            ((and (null segs)
                  (null (upad:project-com en (cal:2d (trans (cadr sel) 1 0)))))
             (princ (strcat "\nA " (cdr (assoc 0 ed))
                            " is not something UPADOVER can measure along"
                            " - select the pool wall.")))
            ((< tot 1e-9)
             (princ "\nThat perimeter has no length."))
            (t
             (setq closed (upad:isclosed en segs)
                   cands  (upad:collect-points))
             (princ (strcat "\nUPADOVER: "
                            (if closed
                              (strcat "a closed perimeter, " (upad:ft tot)
                                      " round.")
                              (strcat "an open run, " (upad:ft tot)
                                      " long."))
                            "  Whole at the next question pads all of it."
                            (if cands
                              (strcat "  " (itoa (length cands))
                                      " survey point(s) can be named by"
                                      " number.")
                              "")))
             (setq stage 2))))))

      ;; --- 2. where the pads start -- or Whole, for all of it ---------
      ((= stage 2)
       (setq e0 (upad:askpoint "Where the pads start - click it, or type a point number"
                               T T cands))
       (cond
         ((eq e0 'UPAD-BACK) (setq stage 1))
         ;; the whole curve, end to end: a line or a polyline drawn as
         ;; the stretch that needs pads IS the answer to both questions,
         ;; so neither is put.  It starts where the curve starts, runs
         ;; its whole length, and on a closed one comes back round to
         ;; where it began
         ((eq e0 'UPAD-WHOLE)
          (setq whole    T
                base0    (upad:point-at en segs 0.0)
                s0       0.0
                sgn      1.0
                runlen   tot
                otherlen nil
                asked    nil
                stage    6))
         (t
          (setq loc (upad:locate en segs (upad:cd-pt e0)))
          (if (null loc)
            (princ (strcat "\nThe perimeter cannot be read under that"
                           " pick - click nearer the wall."))
            (progn
              (setq base0 (car loc)
                    s0    (cadr loc))
              (upad:say-landed e0 base0 "start")
              (setq stage 3))))))

      ;; --- 3. and where they end --------------------------------------
      ((= stage 3)
       (setq e1 (upad:askpoint "Where the pads end - click it, or type a point number"
                               nil T cands))
       (cond
         ((eq e1 'UPAD-BACK) (setq stage 2))
         (t
          (setq loc (upad:locate en segs (upad:cd-pt e1)))
          (cond
            ((null loc)
             (princ (strcat "\nThe perimeter cannot be read under that"
                            " pick - click nearer the wall.")))
            (t
             (setq base1 (car loc)
                   s1    (cadr loc)
                   ;; how far apart the two ends are along the wall, the
                   ;; nearer way round: on a closed wall a station either
                   ;; side of the seam reads as a whole perimeter apart
                   ;; and is the same place
                   gap   (if closed
                           (min (upad:wrap (- s1 s0) tot)
                                (upad:wrap (- s0 s1) tot))
                           (abs (- s1 s0))))
             (cond
               ;; one point cannot be two ends: a run from a place back
               ;; to itself is either nothing or the whole perimeter, and
               ;; guessing which is not this command's to do
               ((< gap upad:*fuzz*)
                (princ (strcat "\nThat is where the run already starts -"
                               " the two ends have to be different"
                               " places on the wall.  (Whole at the first"
                               " question pads all of it.)")))
               (t
                (upad:say-landed e1 base1 "end")
                (setq stage 4))))))))

      ;; --- 4. which way round.  The shorter stretch is what "from here
      ;;        to there" means, unless the two are near enough the same
      ;;        that calling one shorter would be a coin toss ----------
      ((= stage 4)
       (cond
         ((not closed)
          ;; an open wall has one stretch between two points
          (setq sgn       (if (> s1 s0) 1.0 -1.0)
                runlen    (abs (- s1 s0))
                otherlen  nil
                asked     nil
                stage     6))
         (t
          (setq lf (upad:wrap (- s1 s0) tot)
                lb (- tot lf))
          (if (upad:even-p lf lb)
            (setq stage 5)
            (progn
              (setq sgn      (if (< lf lb) 1.0 -1.0)
                    runlen   (min lf lb)
                    otherlen (max lf lb)
                    asked    nil
                    stage    6))))))

      ;; --- 5. ...and when it would be, the drafter says which ---------
      ((= stage 5)
       (princ (strcat "\nUPADOVER: the two ways round are " (upad:ft lf)
                      " and " (upad:ft lb)
                      " - near enough the same that which one you mean is"
                      " yours to say."))
       (setq pick (upad:askpt "Click a spot the run passes through" T))
       (cond
         ((eq pick 'UPAD-BACK) (setq stage 3))
         (t
          (setq loc (upad:locate en segs (cal:2d (trans pick 1 0))))
          (if (null loc)
            (princ (strcat "\nThe perimeter cannot be read there - click"
                           " nearer the wall, on the way round the pads"
                           " go."))
            (progn
              (if (upad:far-side-p (cadr loc) s0 s1 tot)
                (setq sgn -1.0 runlen lb otherlen lf)
                (setq sgn 1.0 runlen lf otherlen lb))
              (setq asked T
                    stage 6))))))

      ;; --- 6. lay the pads -------------------------------------------
      ((= stage 6)
       (upad:ensure-block doc blkname padsize)
       (cal:ensure-layer upad:*layer* upad:*layercolor*)
       (setq delta   (upad:block-delta space blkname)
             step    (/ padsize upad:*samples*)
             pts     (upad:walk en segs tot closed s0 sgn runlen step)
             ;; the walk re-derives its first point from the STATION,
             ;; and an arc's point-to-station-to-point round trip is
             ;; exact only to floating point: the grid is anchored on the
             ;; spot the pick landed on instead, so the first pad is
             ;; centred where the run says it starts
             pts     (cons base0 (cdr pts))
             pads    (upad:cover pts padsize upad:*mincontact*)
             ;; the cover CHECKED against the run it was laid for, not
             ;; taken on trust: every sample of the run that no pad
             ;; covers, in the length that stands for
             nbare   (* (upad:bare pts pads (/ padsize 2.0)) step))
       (foreach e pads
         (upad:insert-pad space blkname e delta))
       (princ (strcat "\nUPADOVER: " (itoa (length pads)) " "
                      (upad:in padsize) " pad(s) on layer \"" upad:*layer*
                      "\", covering "
                      (if whole
                        (strcat "the whole " (upad:ft runlen) " of it"
                                (if closed
                                  ", back round to where it started."
                                  ", end to end."))
                        (strcat (upad:ft runlen) " of perimeter from "
                                (upad:endname e0 "the start you clicked")
                                " to "
                                (upad:endname e1 "the end you clicked")
                                "."))))
       (if otherlen
         (princ (strcat "\nUPADOVER: "
                        (if asked "the way you clicked"
                          "the shorter way round")
                        ", " (upad:ft runlen) " against " (upad:ft otherlen)
                        " the other way.")))
       (if (> nbare (/ step 2.0))
         ;; the one thing that can stop a cover: a run that comes back
         ;; within a pad's width of itself.  A pad there would lie over
         ;; one already down, so it is not laid, and the drafter is told
         ;; exactly how much wall that leaves rather than finding out on
         ;; site
         (princ (strcat "\nUPADOVER: " (upad:ft nbare)
                        " of the run is left bare - a pad there would lie"
                        " over one already down"
                        (if (and whole closed)
                          ", where the loop closes back on itself."
                          ".")))
         (princ (strcat "\nUPADOVER: the pads follow the wall and"
                        " interlock - none lies over another, and each"
                        " shares an edge with the one the run came off,"
                        " so the wall is under pads "
                        (if (and whole closed)
                          "the whole way round."
                          (strcat "from end to end, both ends carried past"
                                  " rather than stopped on.")))))
       (setq done T))))

  (if undo-open (setq undo-open (cal:undoend)))
  (cal:sysrestore)
  (if lzd:end (lzd:end "UPADOVER"))
  (princ))

(if (not *calofin-quiet*)
  (princ (strcat "\nUPADOVER " *upadover-version*
                 " loaded.  Type UPADOVER to run.")))
(princ)
