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
;;;   Every pad sits on ONE grid of pad-sized cells, anchored on the
;;;   first pad -- which is centred on the start.  That one fact is what
;;;   the promise rests on: two cells of a grid either share a full edge
;;;   or stand apart, so pads laid this way can no more overlap than
;;;   floor tiles can.
;;;
;;;   The run is then walked end to end, and every cell it passes
;;;   through gets a pad.  The wall is therefore inside a pad at every
;;;   point of the run: the cover is not a row of pads centred on the
;;;   wall with the corners hoped over, it is the cells the wall
;;;   actually crosses.  Where the run leaves one cell it is already
;;;   inside the next, because the two share the edge it crossed.
;;;
;;;   The one place two cells meet at a point rather than along an edge
;;;   is a grid CORNER, and a run at 45 degrees crosses one every pad.
;;;   A cover that hung on that would be two pads touching at a corner
;;;   with the wall threading the junction between them, which is a
;;;   break in everything but topology -- so the pad beside it goes in
;;;   too and the pair share an edge like every other.
;;;
;;;   The ends are carried past, not stopped at: the first pad is
;;;   centred ON the start point, so the cover begins half a pad before
;;;   it, and the pad the far end falls in runs past that end rather
;;;   than stopping on it.  A pad past the point is concrete nobody
;;;   needed; a wall short of one is the thing the run exists to
;;;   prevent, so that is the direction to err in.
;;;
;;; What it reports
;;;   How many pads, on which layer, how much perimeter they cover and
;;;   between which two points; which way round it went and what the
;;;   other way would have been; and how many pads went in to bridge a
;;;   corner crossing.  A pick that had to be projected onto the wall is
;;;   named with the distance it moved.
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
(setq *upadover-version* "v1.1")

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

;; Nearest whole number, negatives included: (fix (+ x 0.5)) truncates
;; toward zero and would round -1.6 to -1, which puts a pad one cell out
;; on every run left of or below its start.
(defun upad:round (x)
  (if (< x 0.0) (- (fix (+ 0.5 (- x)))) (fix (+ 0.5 x))))

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

;; Every survey point in the drawing, as (position name).
(defun upad:collect-points ( / ss i en ed typ p nm out)
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
      ((and (= (type v) 'STR) (member v '("Back" "Undo")))
       (setq out 'UPAD-BACK done T))
      ((and (= (type v) 'STR) (= v "Whole"))
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
;;;  Every pad sits on one grid of pad-sized cells anchored on the first
;;;  of them, and a cell either shares a full edge with its neighbour or
;;;  stands clear of it -- which is the whole of the no-overlap promise.
;;;  The run is walked end to end and every cell it passes through gets a
;;;  pad, which is the whole of the no-gap one.
;;; ----------------------------------------------------------------------

;; The cell P falls in, as (i j) counted from the cell centred on ORG.
(defun upad:cell (p org pitch)
  (list (upad:round (/ (- (car p) (car org)) pitch))
        (upad:round (/ (- (cadr p) (cadr org)) pitch))))

(defun upad:cell-ctr (c org pitch)
  (list (+ (car org)  (* (car c) pitch))
        (+ (cadr org) (* (cadr c) pitch))))

;; T when cell C already has a pad.  OUT holds (cell kind) entries.
(defun upad:seen (c out / hit e)
  (foreach e out (if (equal (car e) c) (setq hit T)))
  hit)

;; Which of the two cells beside a corner crossing the run really passes
;; through.  The middle of the step says so wherever the crossing is off
;; the corner at all; dead on it -- a run at 45 degrees through the
;; anchor crosses corner after corner exactly -- the axis the run is
;; moving along faster decides, so the same run always answers the same
;; way.
(defun upad:bridge (cur nxt a b org pitch / h v mid)
  (setq h   (list (car nxt) (cadr cur))     ; across the x edge first
        v   (list (car cur) (cadr nxt))     ; across the y edge first
        mid (upad:cell (cal:v* (cal:v+ a b) 0.5) org pitch))
  (cond ((equal mid h) h)
        ((equal mid v) v)
        ((>= (abs (- (car b) (car a))) (abs (- (cadr b) (cadr a)))) h)
        (t v)))

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

;; The pads the run needs, in the order it walks them: (centre kind),
;; kind "run" for a cell the run passes through and "bridge" for one
;; that goes in beside a corner crossing so the two pads either side of
;; it share an edge rather than a point.  PTS is the walk above, and its
;; first point is where the grid is anchored -- the first pad is centred
;; on the start, so the cover begins half a pad before it.
(defun upad:cover (pts pitch / org out cur nxt prv br p)
  (setq org (car pts)
        cur (list 0 0)
        out (list (list cur "run"))
        prv (car pts))
  (foreach p (cdr pts)
    (setq nxt (upad:cell p org pitch))
    (if (not (equal nxt cur))
      (progn
        ;; both indices moved: the run crossed a grid corner, where two
        ;; cells meet at a point and a cover would hang on nothing
        (if (and (/= (car nxt) (car cur)) (/= (cadr nxt) (cadr cur)))
          (progn
            (setq br (upad:bridge cur nxt prv p org pitch))
            (if (not (upad:seen br out))
              (setq out (cons (list br "bridge") out)))))
        (if (not (upad:seen nxt out))
          (setq out (cons (list nxt "run") out)))
        (setq cur nxt)))
    (setq prv p))
  (mapcar '(lambda (e) (list (upad:cell-ctr (car e) org pitch) (cadr e)))
          (reverse out)))

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
                     nbridge blkname padsize e gap whole)

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
        space     (vla-get-Block (vla-get-ActiveLayout doc))
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
             pts     (upad:walk en segs tot closed s0 sgn runlen
                                (/ padsize upad:*samples*))
             ;; the walk re-derives its first point from the STATION,
             ;; and an arc's point-to-station-to-point round trip is
             ;; exact only to floating point: the grid is anchored on the
             ;; spot the pick landed on instead, so the first pad is
             ;; centred where the run says it starts
             pts     (cons base0 (cdr pts))
             pads    (upad:cover pts padsize)
             nbridge 0)
       (foreach e pads
         (upad:insert-pad space blkname (car e) delta)
         (if (= (cadr e) "bridge") (setq nbridge (1+ nbridge))))
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
       (if (> nbridge 0)
         (princ (strcat "\nUPADOVER: " (itoa nbridge)
                        " of them bridge a grid corner the run crosses, so"
                        " the pads either side of it share an edge rather"
                        " than a point.")))
       (princ (strcat "\nUPADOVER: the pads interlock - none overlaps"
                      " another, and where the run leaves one it is"
                      " already inside the next, so it is under pads "
                      (if (and whole closed)
                        "the whole way round."
                        (strcat "from end to end, both ends carried past"
                                " rather than stopped on."))))
       (setq done T))))

  (if undo-open (setq undo-open (cal:undoend)))
  (cal:sysrestore)
  (if lzd:end (lzd:end "UPADOVER"))
  (princ))

(if (not *calofin-quiet*)
  (princ (strcat "\nUPADOVER " *upadover-version*
                 " loaded.  Type UPADOVER to run.")))
(princ)
