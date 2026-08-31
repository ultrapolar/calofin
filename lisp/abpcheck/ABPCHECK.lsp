;;; ======================================================================
;;; ABPCHECK.lsp  --  how far every survey point sits off the drawn lines
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  ABPCHECK        measure every point against the nearest
;;;                            line and write the report
;;;            ABPCHECKVER     print the loaded version
;;;            ABPCHECKRESCUE  remove the report and the red rings
;;; ======================================================================
;;;
;;;  Forked from ABHD, which fits a perimeter THROUGH the survey points
;;;  and rings the ones it could not hold.  ABPCHECK does only the
;;;  measuring half, over a drawing that is already drawn: highlight the
;;;  whole sheet, say how far off is too far, and it reports every point
;;;  with the distance to the nearest line -- worst first, the ones over
;;;  the limit in red.
;;;
;;;  WHAT IT MEASURES
;;;
;;;   1. THE POINTS.  Every POINT entity in the selection, every "ab_pt"
;;;      block wherever it sits, and any other block dropped on the
;;;      POINTS layer.  A point block's own surveyed number (its
;;;      "number" attribute) is what the report calls it; a point with
;;;      no number of its own is numbered in the order it was read, so
;;;      "Pt. 17" always means something you can find.
;;;      Points closer together than abp:*exact-eps* are one point --
;;;      a double-shot is not two findings.
;;;
;;;   2. THE LINES.  Every LINE, ARC, CIRCLE, LWPOLYLINE and 2D POLYLINE
;;;      in the selection, broken into (start end bulge) segments.  The
;;;      distance from a point to a segment is measured to the segment
;;;      ITSELF, not to its ends: perpendicular where the foot lands on
;;;      the run, to the nearer end where it does not.  A point's
;;;      finding is its distance to the nearest of them all.
;;;
;;;   3. THE LIMIT.  You say what counts as too far (Enter takes the
;;;      last answer, 1" to start with).  Points over it are the
;;;      report's red rows and are ringed in the drawing so they can be
;;;      zoomed to; points under it are listed smaller, worst first, so
;;;      the near-misses are visible without hunting.
;;;
;;;   4. AN ABPCHECK REPORT (MTEXT) is placed to the RIGHT of the
;;;      drawing, sized to scale with it: a large title, the date and
;;;      version under it, a verdict, then the findings under underlined
;;;      section headings.  Rows read
;;;
;;;          Pt. 17    closest line is 0'-1 7/8" away
;;;
;;;      Problems in RED at full size, advice in CYAN, points that check
;;;      out smaller.
;;;
;;;  ABPCHECK writes nothing but its report and its rings, both on their
;;;  own layers and both stamped as its own, so ABPCHECKRESCUE takes
;;;  them away again without touching anything you drew.  Splines and
;;;  ellipses are counted and named in the report rather than measured
;;;  -- the segment math does not cover them, and a checker that
;;;  silently ignored geometry would report a point as "off" when it is
;;;  sitting on a spline.
;;; ======================================================================

;;; -------------------- version -----------------------------------------
;;;  The banner form tools/release_lisp.py reads (lowercase name, "v",
;;;  one dot).  Bump it with every change and regenerate releases/.

(setq *abpcheck-version* "v1.2")

;;; -------------------- tunables ----------------------------------------

;; Where the survey points live, and what a point block calls its
;; number -- ABHD's *PF-POINT-LAYER* / *PF-POINT-BLOCK* / *PF-PT-TAG*.
(setq abp:*pt-layer* "POINTS")    ; layer holding the survey points
(setq abp:*pt-block* "ab_pt")     ; block name whose INSERTs mark points
(setq abp:*pt-tag*   "number")    ; the attribute carrying the number

;; How far off the nearest line is too far.  The command asks, Enter
;; takes what is here, and the answer is remembered for the session.
(setq abp:*limit* 1.0)            ; 1 inch

;; Two points closer than this are the same shot, not two.
(setq abp:*exact-eps* 1.0e-6)

;; Marking and report.
(setq abp:*sysold*       nil)     ; saved sysvars, restored on the way out
(setq abp:*miss-layer*   "ABPCHECK-MISS")
(setq abp:*miss-color*   1)       ; red: the points that are too far off
(setq abp:*report-layer* "ABPCHECK-REPORT")
(setq abp:*report-color* 3)
(setq abp:*flag-color*   1)       ; red rows
(setq abp:*advice-color* 4)       ; cyan: advice, not a failure
(setq abp:*green-scale*  0.75)    ; height of a row that checked out
(setq abp:*report-chars* 48.0)    ; report column width, in text heights
(setq abp:*ring-scale*   1.2)     ; ring radius, in report text heights
(setq abp:*clear-shown*  10)      ; how many within-limit points are listed

;;; -------------------- generic helpers ----------------------------------
;;;  A self-contained file: it carries its own helpers.

(defun abp:2d (p) (list (car p) (cadr p)))
(defun abp:dist (a b) (distance (abp:2d a) (abp:2d b)))
(defun abp:v- (a b) (mapcar '- (abp:2d a) (abp:2d b)))
(defun abp:v+ (a b) (mapcar '+ (abp:2d a) (abp:2d b)))
(defun abp:v* (v s) (list (* (car v) s) (* (cadr v) s)))
(defun abp:dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))
(defun abp:mid (a b) (abp:v* (abp:v+ a b) 0.5))
(defun abp:perp (v) (list (- (cadr v)) (car v))) ; rotate 90 deg CCW

;; normalize an angle into [0, 2pi)
(defun abp:angnorm (a)
  (while (< a 0.0) (setq a (+ a pi pi)))
  (while (>= a (+ pi pi)) (setq a (- a pi pi)))
  a)

;; Tangent with the angle clamped just short of +/-90 degrees, so a
;; degenerate half-turn bulge yields a huge but finite number instead
;; of dividing by zero.
(defun abp:tan (x)
  (cond ((> x  1.5697) (setq x  1.5697))    ; 89.94 deg
        ((< x -1.5697) (setq x -1.5697)))
  (/ (sin x) (cos x)))

;; Pad S with spaces to width W.
(defun abp:pad (s w)
  (while (< (strlen s) w) (setq s (strcat s " ")))
  s)

;; zero-pad an integer to two digits
(defun abp:zeropad2 (n)
  (if (< n 10) (strcat "0" (itoa n)) (itoa n)))

;; "YYYY-MM-DD HH:MM" -- CDATE decoded arithmetically so DIMZIN (which
;; trims rtos output) cannot mangle it.
(defun abp:datestr (/ d dd tt)
  (setq d  (getvar "CDATE")
        dd (fix d)
        tt (- d dd))
  (strcat (itoa (fix (/ dd 10000))) "-"
          (abp:zeropad2 (rem (fix (/ dd 100)) 100)) "-"
          (abp:zeropad2 (rem dd 100)) " "
          (abp:zeropad2 (fix (+ (* tt 100) 1e-6))) ":"
          (abp:zeropad2 (rem (fix (+ (* tt 10000) 1e-4)) 100))))

;; The sysvar snapshot lives in a GLOBAL and is taken only when no
;; snapshot is already pending: if a previous run died before restoring,
;; the stale snapshot still holds the user's TRUE settings.
(defun abp:syssave (vars / v)
  (if (not abp:*sysold*)
      (foreach v vars
        (if (/= nil (getvar v))
            (setq abp:*sysold*
                  (append abp:*sysold* (list (cons v (getvar v)))))))))

(defun abp:sysrestore ( / p)
  (foreach p abp:*sysold* (setvar (car p) (cdr p)))
  (setq abp:*sysold* nil))

;; Create the output layer, or - when it already exists - make sure it
;; is on, thawed and unlocked.  Without this a successful run onto a
;; frozen or switched-off layer looks like the command did nothing.
;; Returns the layer NAME in every case.
(defun abp:ensure-layer (name color / rec ed flags col fixed)
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

;; entmake an MTEXT, splitting into 250-char DXF chunks; returns the
;; new ename, or nil.  MTEXT carries at most 250 characters in group 1,
;; so a report that skipped the split would lose everything past the
;; first 250 characters.
(defun abp:mtext (ins hgt wid str lay / dxf)
  (setq dxf (list '(0 . "MTEXT")
                  '(100 . "AcDbEntity")
                  (cons 8 lay)
                  '(100 . "AcDbMText")
                  (cons 10 ins)
                  (cons 40 hgt)
                  (cons 41 wid)
                  '(71 . 1)))                  ; attachment: top-left
  (while (> (strlen str) 250)
    (setq dxf (append dxf (list (cons 3 (substr str 1 250))))
          str (substr str 251)))
  (if (entmake (append dxf (list (cons 1 str))))
    (entlast)))

;; The name carried by a point block, read from its TAG attribute; when
;; the block has no such attribute, the first attribute whose value
;; reads as a number is taken instead (survey exports do not all use
;; the ab_pt tag).  nil when neither exists.
(defun abp:block-number (en tag / sub ed val fall v)
  (setq sub (entnext en) val nil fall nil)
  (while (and sub
              (setq ed (entget sub))
              (= "ATTRIB" (cdr (assoc 0 ed))))
    (setq v (cdr (assoc 1 ed)))
    (if (and (null val)
             (cdr (assoc 2 ed))
             (= (strcase (cdr (assoc 2 ed))) (strcase tag)))
      (setq val v))
    (if (and (null fall) v (distof v 2))
      (setq fall v))
    (setq sub (entnext sub)))
  (if val val fall))

;;; -------------------- arc / segment geometry --------------------------
;;;  A segment is (startPt endPt bulge), 2D points -- ABHD's shape, and
;;;  the reason the fork was worth making: the distance-to-a-bulged-
;;;  segment math is already proven there.

;; Center of the circle through three points; nil when they are
;; collinear.  (pf:circumcenter, abhd.lsp:388 -- the 2-element form,
;; since every point here is 2D.)
(defun abp:circumcenter (pa pb pc / x1 y1 x2 y2 x3 y3 d s1 s2 s3)
  (setq x1 (car pa) y1 (cadr pa)
        x2 (car pb) y2 (cadr pb)
        x3 (car pc) y3 (cadr pc)
        d  (* 2.0 (+ (* x1 (- y2 y3)) (* x2 (- y3 y1)) (* x3 (- y1 y2)))))
  (if (< (abs d) 1.0e-10)
    nil
    (progn
      (setq s1 (+ (* x1 x1) (* y1 y1))
            s2 (+ (* x2 x2) (* y2 y2))
            s3 (+ (* x3 x3) (* y3 y3)))
      (list (/ (+ (* s1 (- y2 y3)) (* s2 (- y3 y1)) (* s3 (- y1 y2))) d)
            (/ (+ (* s1 (- x3 x2)) (* s2 (- x1 x3)) (* s3 (- x2 x1))) d)))))

;; Arc geometry of a bulged segment: (center radius angStart angEnd)
;; where the arc runs CCW from angStart to angEnd when bulge > 0 and CW
;; when bulge < 0.  nil for a straight segment.  (pf:arc-geom.)
(defun abp:arc-geom (p1 p2 b / ch dir apex c)
  (if (< (abs b) 1.0e-9)
    nil
    (progn
      (setq p1   (abp:2d p1)
            p2   (abp:2d p2)
            ch   (abp:dist p1 p2)
            dir  (abp:v* (abp:v- p2 p1) (/ 1.0 ch))
            ;; sagitta = (chord/2)*bulge; a positive (CCW) bulge apex
            ;; lies to the RIGHT of the p1->p2 chord direction
            apex (abp:v+ (abp:mid p1 p2)
                         (abp:v* (abp:perp dir) (* -0.5 ch b)))
            c    (abp:circumcenter p1 apex p2))
      (if (null c)
        nil
        (list c (abp:dist c p1) (angle c p1) (angle c p2))))))

;; Distance from point P to segment (p1 p2 bulge).  Straight: project
;; onto the run and clamp to its ends.  Curved: the radial distance
;; when P falls inside the sweep, the nearer endpoint when it does not.
;; (pf:seg-dist, abhd.lsp:446.)
(defun abp:seg-dist (p seg / p1 p2 b v w len2 t2 g c r a1 a2 ap sweep rel)
  (setq p  (abp:2d p)
        p1 (abp:2d (car seg))
        p2 (abp:2d (cadr seg))
        b  (caddr seg))
  (if (< (abs b) 1.0e-9)
    (progn
      (setq v    (abp:v- p2 p1)
            w    (abp:v- p p1)
            len2 (abp:dot v v))
      (if (< len2 1.0e-20)
        (abp:dist p p1)
        (progn
          (setq t2 (/ (abp:dot w v) len2))
          (if (< t2 0.0) (setq t2 0.0))
          (if (> t2 1.0) (setq t2 1.0))
          (abp:dist p (abp:v+ p1 (abp:v* v t2))))))
    (progn
      (setq g (abp:arc-geom p1 p2 b))
      (if (null g)
        (min (abp:dist p p1) (abp:dist p p2))
        (progn
          (setq c  (car g)   r  (cadr g)
                a1 (caddr g) a2 (cadddr g)
                ap (angle c p))
          (if (> b 0.0)
            (setq sweep (abp:angnorm (- a2 a1)) rel (abp:angnorm (- ap a1)))
            (setq sweep (abp:angnorm (- a1 a2)) rel (abp:angnorm (- ap a2))))
          (if (<= rel sweep)
            (abs (- (abp:dist p c) r))
            (min (abp:dist p p1) (abp:dist p p2))))))))

;;; -------------------- entity -> segments ------------------------------

(defun abp:lw-segs (ed / pts bls item segs n closed)
  ;; collect (10) vertices and their (42) bulges, in order
  (setq pts nil bls nil)
  (foreach item ed
    (cond
      ((= (car item) 10)
       (setq pts (cons (abp:2d (cdr item)) pts)
             bls (cons 0.0 bls)))
      ((and (= (car item) 42) bls)
       (setq bls (cons (cdr item) (cdr bls))))))
  (setq pts    (reverse pts)
        bls    (reverse bls)
        closed (= 1 (logand 1 (cdr (assoc 70 ed))))
        segs   nil
        n      0)
  (while (< n (1- (length pts)))
    (setq segs (cons (list (nth n pts) (nth (1+ n) pts) (nth n bls)) segs)
          n    (1+ n)))
  ;; the closing run exists only on a closed polyline, and only when
  ;; the last vertex is not already sitting on the first
  (if (and closed
           (> (length pts) 2)
           (> (abp:dist (last pts) (car pts)) abp:*exact-eps*))
    (setq segs (cons (list (last pts) (car pts) (last bls)) segs)))
  (reverse segs))

(defun abp:pl-segs (en / ed sub pts bls segs n closed)
  ;; heavy (old-style) 2D POLYLINE: walk its VERTEX sub-entities
  (setq ed     (entget en)
        closed (= 1 (logand 1 (cdr (assoc 70 ed))))
        pts    nil
        bls    nil
        sub    (entnext en))
  (while (and sub (= "VERTEX" (cdr (assoc 0 (setq ed (entget sub))))))
    ;; skip spline/fit control vertices (flag bits 1 and 16)
    (if (= 0 (logand 17 (cond ((cdr (assoc 70 ed))) (0))))
      (setq pts (cons (abp:2d (cdr (assoc 10 ed))) pts)
            bls (cons (cond ((cdr (assoc 42 ed))) (0.0)) bls)))
    (setq sub (entnext sub)))
  (setq pts (reverse pts) bls (reverse bls) segs nil n 0)
  (while (< n (1- (length pts)))
    (setq segs (cons (list (nth n pts) (nth (1+ n) pts) (nth n bls)) segs)
          n    (1+ n)))
  (if (and closed (> (length pts) 2))
    (setq segs (cons (list (last pts) (car pts) (last bls)) segs)))
  (reverse segs))

(defun abp:ent-segs (en / ed typ c r a1 a2 delta)
  (setq ed  (entget en)
        typ (cdr (assoc 0 ed)))
  (cond
    ((= typ "LINE")
     (list (list (abp:2d (cdr (assoc 10 ed)))
                 (abp:2d (cdr (assoc 11 ed)))
                 0.0)))
    ((= typ "ARC")
     (setq c     (abp:2d (cdr (assoc 10 ed)))
           r     (cdr (assoc 40 ed))
           a1    (cdr (assoc 50 ed))
           a2    (cdr (assoc 51 ed))
           delta (abp:angnorm (- a2 a1)))
     (if (< delta 1.0e-10) (setq delta (* 2.0 pi)))
     ;; a full-circle arc cannot be one bulged segment (its bulge is
     ;; infinite): hand back two semicircles instead
     (if (> delta (- (* 2.0 pi) 1.0e-9))
       (list (list (polar c a1 r) (polar c (+ a1 pi) r) 1.0)
             (list (polar c (+ a1 pi) r) (polar c a1 r) 1.0))
       (list (list (polar c a1 r) (polar c a2 r) (abp:tan (/ delta 4.0))))))
    ((= typ "CIRCLE")
     (setq c (abp:2d (cdr (assoc 10 ed)))
           r (cdr (assoc 40 ed)))
     (list (list (polar c 0.0 r) (polar c pi r) 1.0)
           (list (polar c pi r) (polar c 0.0 r) 1.0)))
    ((= typ "LWPOLYLINE") (abp:lw-segs ed))
    ((= typ "POLYLINE") (abp:pl-segs en))
    (T nil)))

;;; -------------------- points ------------------------------------------
;;;  A point record is (x y name): the name is what the report calls it,
;;;  so a finding reads "Pt. 17" whether 17 came off the block or off
;;;  the reading order.

(defun abp:pt (p nm) (list (car p) (cadr p) nm))
(defun abp:pt-name (q) (if (caddr q) (caddr q) "?"))

;; drop every point within EPS of a kept one, order preserved -- a
;; double-shot is one point, not two findings
(defun abp:dedupe (pts eps / out q p dup)
  (foreach q pts
    (setq dup nil)
    (foreach p out
      (if (< (abp:dist p q) eps) (setq dup T)))
    (if (not dup) (setq out (cons q out))))
  (reverse out))

;; Insert (key . val) pair X into the already-sorted list LST, keeping
;; ascending order by the pair's car (key).
(defun abp:ins-car (x lst)
  (cond ((null lst) (list x))
        ((< (car x) (car (car lst))) (cons x lst))
        (T (cons (car lst) (abp:ins-car x (cdr lst))))))

;; Insertion-sort a list of (key . val) pairs ascending by key.
(defun abp:sort-car (lst / out x)
  (foreach x lst (setq out (abp:ins-car x out)))
  out)

;; Bounding box of a point list, as (minx miny maxx maxy).
(defun abp:bbox (pts / x0 y0 x1 y1 q)
  (foreach q pts
    (if (null x0)
      (setq x0 (car q) x1 (car q) y0 (cadr q) y1 (cadr q))
      (setq x0 (min x0 (car q)) x1 (max x1 (car q))
            y0 (min y0 (cadr q)) y1 (max y1 (cadr q)))))
  (if x0 (list x0 y0 x1 y1)))

(defun abp:bw (bb) (- (caddr bb) (car bb)))
(defun abp:bh (bb) (- (cadddr bb) (cadr bb)))

;;; -------------------- reading the selection ---------------------------

;; Everything ABPCHECK needs out of the selection, in one pass:
;;   (points segments splines-skipped out-of-plane own-objects)
;; Its own rings and report are never read back as geometry -- a stale
;; red ring from the last run would otherwise BE the nearest line.
(defun abp:harvest (ss / i en ed typ lay ext nm pts segs npt nspl nocs
                         nmine)
  (setq pts nil segs nil npt 0 nspl 0 nocs 0 nmine 0 i 0)
  (while (< i (sslength ss))
    (setq en (ssname ss i)
          ed (entget en)
          i  (1+ i))
    (if (null ed)
      ;; erased under us by the purge that runs before this - the only
      ;; thing that purge ever takes is ABPCHECK's own work
      (setq nmine (1+ nmine))
      (progn
        (setq typ (cdr (assoc 0 ed))
              lay (strcase (cdr (assoc 8 ed)))
              ext (cdr (assoc 210 ed)))
        (if (or (= lay (strcase abp:*miss-layer*))
                (= lay (strcase abp:*report-layer*))
                (assoc -3 (entget en '("ABPCHECK"))))
          (setq nmine (1+ nmine))
          (progn
            (if (and ext (< (abs (caddr ext)) 0.999))
              (setq nocs (1+ nocs)))
            (cond
              ;; ab_pt blocks are survey points wherever they sit
              ((and (= typ "INSERT")
                    (= (strcase (cdr (assoc 2 ed)))
                       (strcase abp:*pt-block*)))
               (setq npt (1+ npt)
                     nm  (abp:block-number en abp:*pt-tag*)
                     pts (cons (abp:pt (cdr (assoc 10 ed))
                                       (if (and nm (/= nm ""))
                                         nm
                                         (itoa npt)))
                               pts)))
              ;; a plain POINT counts on any layer - the selection is
              ;; explicit, so there is no guessing involved
              ((= typ "POINT")
               (setq npt (1+ npt)
                     pts (cons (abp:pt (cdr (assoc 10 ed)) (itoa npt))
                               pts)))
              ;; other blocks only count as points on the points layer
              ((= typ "INSERT")
               (if (= lay (strcase abp:*pt-layer*))
                 (setq npt (1+ npt)
                       nm  (abp:block-number en abp:*pt-tag*)
                       pts (cons (abp:pt (cdr (assoc 10 ed))
                                         (if (and nm (/= nm ""))
                                           nm
                                           (itoa npt)))
                                 pts))))
              ;; the segment math does not cover these, and guessing
              ;; would report a point sitting ON a spline as off the line
              ((member typ '("SPLINE" "ELLIPSE")) (setq nspl (1+ nspl)))
              (T (setq segs (append segs (abp:ent-segs en))))))))))
  (list (abp:dedupe (reverse pts) abp:*exact-eps*)
        segs nspl nocs nmine))

;; Every point against every segment: (distance . point), ascending.
(defun abp:measure (pts segs / keyed q s d dmin)
  (setq keyed nil)
  (foreach q pts
    (setq dmin nil)
    (foreach s segs
      (setq d (abp:seg-dist q s))
      (if (or (null dmin) (< d dmin)) (setq dmin d)))
    (if dmin (setq keyed (cons (cons dmin q) keyed))))
  (abp:sort-car keyed))

;;; -------------------- report text -------------------------------------
;;;  A report row is (text . level): level nil = checked out, 1 = too
;;;  far, 2 = advice, 3 = a section heading.  The four render
;;;  differently in the MTEXT.

(defun abp:row (s lvl) (cons s lvl))
(defun abp:row-txt (r) (car r))
(defun abp:row-lvl (r) (cdr r))
(defun abp:lvl-p (r n) (and (abp:row-lvl r) (= (abp:row-lvl r) n)))

(defun abp:red (s)
  (strcat "{\\C" (itoa abp:*flag-color*) ";" s "}"))

(defun abp:cyan (s)
  (strcat "{\\C" (itoa abp:*advice-color*) ";" s "}"))

(defun abp:small (s)
  (strcat "{\\H" (rtos abp:*green-scale* 2 2) "x;" s "}"))

;; The report's title line: half again the base height.
(defun abp:big (s)
  (strcat "{\\H1.5x;" s "}"))

;; A section heading: underlined, with a thin blank line above it so
;; the sections read as blocks.
(defun abp:hdg (s)
  (strcat "{\\H0.4x;\\P}{\\L" s "}"))

;; Findings are indented two spaces under their heading; the indent
;; sits INSIDE the colour/height wrap so a row still starts with its
;; colour code.
(defun abp:render (r)
  (cond ((abp:lvl-p r 3) (abp:hdg (abp:row-txt r)))
        ((abp:lvl-p r 1) (abp:red (strcat "  " (abp:row-txt r))))
        ((abp:lvl-p r 2) (abp:cyan (strcat "  " (abp:row-txt r))))
        (t (abp:small (strcat "  " (abp:row-txt r))))))

;; The one finding line, the shape the report was asked for:
;;     Pt. 17    closest line is 0'-1 7/8" away
(defun abp:finding (q)
  (strcat "Pt. " (abp:pad (abp:pt-name (cdr q)) 6)
          "closest line is " (rtos (car q) 4 4) " away"))

;; Distance as the report writes it, for prose (the limit, mostly).
(defun abp:dstr (d) (rtos d 4 4))

;; The findings, worst first: everything over the limit under one
;; heading, then the near misses under another, capped so a 200-point
;; survey does not write 200 lines of "checks out".  KEYED is ascending
;; by distance, so reversing it puts the worst at the top.
(defun abp:rows (keyed limit nspl nocs / rows bad ok q n)
  (setq rows nil bad nil ok nil)
  (foreach q (reverse keyed)
    (if (> (car q) limit)
      (setq bad (cons q bad))
      (setq ok (cons q ok))))
  (setq bad (reverse bad) ok (reverse ok))
  (if bad
    (progn
      (setq rows (cons (abp:row (strcat "POINTS TOO FAR OFF ("
                                        (itoa (length bad)) ")") 3)
                       rows))
      (foreach q bad
        (setq rows (cons (abp:row (abp:finding q) 1) rows)))))
  (if ok
    (progn
      (setq rows (cons (abp:row (strcat "POINTS ON THE LINE ("
                                        (itoa (length ok)) ")") 3)
                       rows)
            n    0)
      (foreach q ok
        (if (< n abp:*clear-shown*)
          (setq rows (cons (abp:row (abp:finding q) nil) rows)))
        (setq n (1+ n)))
      (if (> n abp:*clear-shown*)
        (setq rows (cons (abp:row (strcat "... and "
                                          (itoa (- n abp:*clear-shown*))
                                          " more, every one of them"
                                          " within the limit")
                                  nil)
                         rows)))))
  ;; what the run could not measure is said out loud, never swallowed
  (if (or (> nspl 0) (> nocs 0))
    (progn
      (setq rows (cons (abp:row "NOT MEASURED" 3) rows))
      (if (> nspl 0)
        (setq rows (cons (abp:row
                           (strcat (itoa nspl) " spline/ellipse object(s)"
                                   " were not measured - a point sitting"
                                   " on one may be listed as off the line")
                           2)
                         rows)))
      (if (> nocs 0)
        (setq rows (cons (abp:row
                           (strcat (itoa nocs) " selected object(s) are not"
                                   " drawn in the world plane - distances"
                                   " to them are measured flat (XY) and"
                                   " may be wrong")
                           2)
                         rows)))))
  (reverse rows))

;;; -------------------- the report --------------------------------------

;; The whole report, to the RIGHT of what was measured and sized to
;; scale with it, as the sibling checkers place theirs.  Returns
;; (too-far-count advisory-count text-height) -- the height comes back
;; because the rings are sized to it, so both scale with the drawing.
(defun abp:write-report (rows bb limit / nlin ref h ins txt r nbad nadv)
  (abp:ensure-layer abp:*report-layer* abp:*report-color*)
  (setq nbad 0 nadv 0)
  (foreach r rows
    (cond ((abp:lvl-p r 1) (setq nbad (1+ nbad)))
          ((abp:lvl-p r 2) (setq nadv (1+ nadv)))))
  ;; height: the head is title (1.5) + date + verdict (1.2) + legend; a
  ;; heading row is one line plus the 0.4 gap above it
  (setq nlin 4.5)
  (foreach r rows
    (setq nlin (+ nlin (cond ((abp:lvl-p r 3) 1.4)
                             ((abp:row-lvl r) 1.0)
                             (t abp:*green-scale*)))))
  (if (and bb (> (max (abp:bw bb) (abp:bh bb)) 1.0e-8))
    (progn
      (setq ref (max (abp:bh bb) (* 0.25 (abp:bw bb)))
            h   (/ ref (* 1.66 nlin)))
      (if (> h (/ ref 30.0))  (setq h (/ ref 30.0)))
      (if (< h (/ ref 200.0)) (setq h (/ ref 200.0))))
    (setq h 2.5))
  (setq ins (if bb
                (list (+ (caddr bb) (* 0.05 (max (abp:bw bb) 1.0)))
                      (cadddr bb) 0.0)
                (list 0.0 0.0 0.0)))
  ;; the head: a large title, the date and version small under it, the
  ;; verdict, then the legend.  The verdict is wrapped in its height
  ;; code first so it never renders as (or counts among) the finding
  ;; rows, which start with a colour code.
  (setq txt (strcat (abp:big "ABPCHECK REPORT")
                    "\\P"
                    (abp:small (strcat (abp:datestr)
                                       "  -  ABPCHECK "
                                       *abpcheck-version*))
                    "\\P"
                    "{\\H1.2x;"
                    (if (> nbad 0)
                      (abp:red (strcat (itoa nbad) " POINT"
                                       (if (= 1 nbad) "" "S")
                                       " MORE THAN " (abp:dstr limit)
                                       " OFF THE LINE"))
                      (strcat "ALL CLEAR - every point is within "
                              (abp:dstr limit) " of a line"))
                    "}"
                    "\\P"
                    (abp:small
                      (strcat "Too far = more than " (abp:dstr limit)
                              " off the nearest line.  Read-only scan -"
                              " nothing you drew was changed.  Too far in "
                              (abp:red "red")
                              ", advice in " (abp:cyan "cyan")
                              "; points that check out are smaller."))))
  (foreach r rows
    (setq txt (strcat txt "\\P" (abp:render r))))
  (abp:tag-mine (abp:mtext ins h (* abp:*report-chars* h) txt
                           abp:*report-layer*))
  (list nbad nadv h))

;;; -------------------- "this one is mine" stamping ---------------------
;;;  ABPCHECK writes onto layers the drawing may already be using, so it
;;;  must never clear a layer wholesale.  Everything it creates carries
;;;  a small piece of extended data naming this command, and only
;;;  stamped objects are ever erased again.

(defun abp:tag-mine (en / ed)
  (if en
    (progn
      (regapp "ABPCHECK")
      (setq ed (entget en))
      (entmod (append ed (list (list -3 (list "ABPCHECK"
                                              (cons 1000 "ABPCHECK"))))))))
  en)

;; Erase only ABPCHECK's own objects on a layer; anything the user drew
;; there is left alone.  Returns how many went.
(defun abp:purge-mine (name / ss i en n)
  (setq n 0)
  (if (tblsearch "LAYER" name)
    (progn
      (setq ss (ssget "_X" (list (cons 8 name))))
      (if ss
        (progn
          (setq i 0)
          (repeat (sslength ss)
            (setq en (ssname ss i))
            (if (assoc -3 (entget en '("ABPCHECK")))
              (progn (entdel en) (setq n (1+ n))))
            (setq i (1+ i)))))))
  n)

;; Ring every point that is too far off, on its own layer, so the
;; report's rows can be zoomed to instead of hunted for.
(defun abp:ring (keyed limit h / q n)
  (setq n 0)
  (foreach q keyed
    (if (> (car q) limit)
      (progn
        (if (= n 0) (abp:ensure-layer abp:*miss-layer* abp:*miss-color*))
        (abp:tag-mine
          (entmakex (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                          (cons 8 abp:*miss-layer*) '(100 . "AcDbCircle")
                          (cons 10 (list (car (cdr q)) (cadr (cdr q)) 0.0))
                          (cons 40 (* abp:*ring-scale* h)))))
        (setq n (1+ n)))))
  n)

;;; -------------------- asking ------------------------------------------

;; How far off is too far.  A limit is always needed, so there is no NA
;; here: Enter takes the remembered answer and nothing else opts out.
;; initget 6 rejects zero and negatives, as a REQ measurement does.
(defun abp:asklimit (msg dflt / v)
  (initget 6)
  (setq v (getdist (strcat "\n" msg " <" (abp:dstr dflt) ">: ")))
  (if v v dflt))

;;; -------------------- the commands ------------------------------------

;; The selection filter: the points and the geometry they are measured
;; against, plus the two curve types that are counted rather than
;; measured, so the report can say they were left out.
(setq abp:*filter*
  '((0 . "POINT,INSERT,LINE,ARC,CIRCLE,LWPOLYLINE,POLYLINE,SPLINE,ELLIPSE")))

(defun c:ABPCHECK ( / *error* undo-open ss got pts segs nspl nocs nmine
                      keyed rows bb res h nring)
  (defun *error* (msg)
    ;; user settings come back FIRST so nothing below can skip them
    (abp:sysrestore)
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nABPCHECK error: " msg)))
    (princ))
  (abp:syssave '("CMDECHO"))
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_Begin")
  (setq undo-open T)
  (princ "\n\nABPCHECK - how far every point sits off the nearest line.")
  ;; a pickfirst selection if there is one, otherwise ask for it
  (setq ss (ssget "_I" abp:*filter*))
  (if (null ss)
    (progn
      (princ "\nHighlight the drawing to ABPCHECK (Enter = whole drawing): ")
      (setq ss (ssget abp:*filter*))))
  (if (null ss) (setq ss (ssget "_X" abp:*filter*)))
  (if (null ss)
    (princ "\nNothing to check - no points or lines in the drawing.")
    (progn
      ;; markers from an earlier run describe a limit that no longer
      ;; applies; only ABPCHECK's own are removed, never anything else
      (abp:purge-mine abp:*miss-layer*)
      (abp:purge-mine abp:*report-layer*)
      (setq got   (abp:harvest ss)
            pts   (car got)
            segs  (cadr got)
            nspl  (caddr got)
            nocs  (cadddr got)
            nmine (nth 4 got))
      (if (> nmine 0)
        (princ (strcat "\n  (" (itoa nmine)
                       " object(s) from an earlier ABPCHECK were ignored)")))
      (cond
        ((null pts)
         (princ (strcat "\nNo survey points in the selection - looked for"
                        " POINT entities, \"" abp:*pt-block*
                        "\" blocks anywhere, and blocks on layer "
                        abp:*pt-layer* ".")))
        ((null segs)
         (princ (strcat "\n" (itoa (length pts)) " point(s) found, but no"
                        " lines, arcs or polylines to measure them"
                        " against - include the drawn geometry in the"
                        " selection.")))
        (T
         (setq abp:*limit*
               (abp:asklimit "How far off the line is too far?"
                             abp:*limit*))
         (setq keyed (abp:measure pts segs)
               rows  (abp:rows keyed abp:*limit* nspl nocs)
               bb    (abp:bbox pts)
               res   (abp:write-report rows bb abp:*limit*)
               h     (caddr res)
               nring (abp:ring keyed abp:*limit* h))
         (princ (strcat "\n" (itoa (length pts)) " point(s) measured"
                        " against " (itoa (length segs)) " segment(s)."))
         (if (> (car res) 0)
           (princ (strcat "\n" (itoa (car res)) " point(s) more than "
                          (abp:dstr abp:*limit*) " off the nearest line - "
                          (itoa nring) " ringed on layer "
                          abp:*miss-layer* "."))
           (princ (strcat "\nAll clear - every point is within "
                          (abp:dstr abp:*limit*) " of a line.")))
         (princ (strcat "\nReport written on layer " abp:*report-layer*
                        ".  ABPCHECKRESCUE removes both."))))))
  (command "_.UNDO" "_End")
  (setq undo-open nil)
  (abp:sysrestore)
  (princ))

;; Take the report and the rings away again, leaving the drawing as it
;; was - only ABPCHECK's own stamped objects go.
(defun c:ABPCHECKRESCUE ( / *error* undo-open n)
  (defun *error* (msg)
    (abp:sysrestore)
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nABPCHECKRESCUE error: " msg)))
    (princ))
  (abp:syssave '("CMDECHO"))
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_Begin")
  (setq undo-open T)
  (setq n (+ (abp:purge-mine abp:*miss-layer*)
             (abp:purge-mine abp:*report-layer*)))
  (if (> n 0)
    (princ (strcat "\nABPCHECKRESCUE: " (itoa n)
                   " ABPCHECK object(s) removed."))
    (princ "\nABPCHECKRESCUE: nothing of ABPCHECK's left to remove."))
  (command "_.UNDO" "_End")
  (setq undo-open nil)
  (abp:sysrestore)
  (princ))

(defun c:ABPCHECKVER ()
  (princ (strcat "\nABPCHECK " *abpcheck-version* " loaded."))
  (princ))

(princ (strcat "\nABPCHECK " *abpcheck-version*
               " loaded.  Type ABPCHECK to run."))
(princ)
