;;; ======================================================================
;;; CLEARDIM.lsp  --  slide dimension text along its own dimension line
;;;                    until it is readable, and leave the readable ones
;;;                    where they are
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  CLEARDIM       clear the dimension text that is hard to read
;;;            CLEARDIMSCAN   the same pass, read-only: report, move nothing
;;;            CLEARDIMVER    print the loaded version
;;;
;;; A dimension's text has ONE TRACK: the dimension line it belongs to.
;;; Sliding the text along that line is free -- it still reads as the
;;; same dimension, the extension lines still say what was measured, and
;;; nothing about the drawing changes.  Lifting it OFF the line is not
;;; free: the text stops sitting on the thing it measures and AutoCAD
;;; starts drawing a leader to explain where it went.  So CLEARDIM only
;;; ever slides ALONG, never across: the text's perpendicular offset from
;;; its dimension line comes out of the run exactly as it went in.
;;;
;;; What counts as hard to read is anything under the text:
;;;
;;;   * another dimension's text sitting on top of it;
;;;   * any other drawing ink -- lines, polyline edges, arcs, circles,
;;;     TEXT, MTEXT -- crossing the letters;
;;;   * the dimension lines and the extension lines of the OTHER
;;;     dimensions in the sweep, which are ink like any other;
;;;   * this dimension's OWN extension lines, which cross its track at
;;;     right angles and are the thing text slid too far ends up on.
;;;
;;; Its own dimension line is the one thing that is not an obstacle:
;;; AutoCAD breaks it around the text, which is what a dimension is.
;;;
;;; THE ONE THAT IS ALREADY GOOD DOES NOT MOVE.  That is the whole
;;; policy, and it decides who gives way when two texts want one spot:
;;;
;;;   1. Text that CANNOT move goes down first and keeps its spot --
;;;      a dimension on a locked layer, a dimension with no text, and
;;;      every dimension whose track is not a straight line (angular,
;;;      radius, diameter, ordinate; see "What it will not touch").
;;;   2. Then the text that is clear of every fixed thing in the
;;;      drawing.  It has earned its spot, so it keeps it.
;;;   3. Only then the text that is on top of something.  It is routed
;;;      around everything already placed.
;;;
;;; Inside each of those three the order is reading order -- row by row
;;; down the sheet, left to right along each row -- so two texts that
;;; are each clear of the drawing but not of each other resolve the same
;;; way every run: the first one read keeps its spot and the second
;;; slides.  Nothing is moved that did not have to be.
;;;
;;; A text that has to move goes to the NEAREST clear spot on its track,
;;; found by stepping outward from where it sits and then bisecting back
;;; toward it, so the move is the smallest one that works.  The two
;;; directions are not equal: the one that takes the text back toward the
;;; middle of its own dimension line is tried first, because the middle
;;; is where a dimension's text belongs.  A text with nowhere clear
;;; within reach (cd:*reach-f*) is LEFT WHERE IT WAS and named in the
;;; report -- a text parked somewhere arbitrary is worse than a text
;;; still sitting on a line, because the drafter can see the second one.
;;;
;;; What it will not touch, and says so rather than guessing:
;;;
;;;   * ANGULAR, RADIUS, DIAMETER and ORDINATE dimensions.  Every one
;;;     of them has a track -- an arc, a radial line, a leader -- and
;;;     not one of them is the straight dimension line this file knows
;;;     how to walk.  Sliding text along a straight line that is not
;;;     the track would take it off the dimension, which is the one
;;;     thing the tool exists not to do.  They are counted in the
;;;     report by kind, and their text is an obstacle everything else
;;;     has to clear.
;;;   * a dimension on a LOCKED layer.  entmod would be refused, and a
;;;     run that silently skipped it would claim a sheet was cleared
;;;     when it was not.
;;;   * a dimension whose text is suppressed (DIMENSION group 1 is a
;;;     single space).  There is no text to be hard to read.
;;;
;;; The whole run is one UNDO group, so a single U puts every text back.
;;; CLEARDIMSCAN is the same analysis with the entmod left out: it says
;;; what CLEARDIM would do and changes nothing.
;;;
;;; How the text box is measured.  A DIMENSION's letters live in its
;;; anonymous block, which is regenerated whenever anything about the
;;; dimension changes, so the box is computed from the dimension itself
;;; instead: group 11 is the middle of the text, the height is the
;;; style's DIMTXT times DIMSCALE (with the dimension's own xdata
;;; overrides applied over the top), and the width is the glyph count at
;;; cd:*charwidth* of that height.  That last one is an ESTIMATE -- a
;;; stroke font's glyphs are not all one width -- so it is a knob, and
;;; raising it makes every box wider and the tool more cautious.
;;;
;;; Versioning: see tools/release_lisp.py at the repo root.  It reads
;;; *cleardim-version* below and stamps a dated, REV-numbered twin of
;;; this file into releases/.
;;; ======================================================================

;;; -------------------- version ---------------------------------------
(setq *cleardim-version* "v1.0")   ; announced on load; release_lisp.py
                                   ; reads this banner and stamps the
                                   ; dated twin in releases/ from it

;;; -------------------- tunables --------------------------------------
;;; Everything about this run somebody might reasonably want different.
;;; Each is read when the command runs, not when the file loads, so a
;;; setq typed at the command line changes the next run.

(setq cd:*charwidth* 0.75)         ; how wide one glyph is taken to be,
                                   ; as a fraction of the text height.
                                   ; The one estimate in the file:
                                   ; raise it and every text box gets
                                   ; wider, so more texts are called
                                   ; hard to read and the ones that
                                   ; move end up further clear

(setq cd:*gap-f* 0.4)              ; breathing room left around a text
                                   ; box on every side, as a multiple
                                   ; of the text height.  0.0 asks only
                                   ; that the ink not actually cross
                                   ; the letters, which is not the same
                                   ; as readable

(setq cd:*step-f* 0.25)            ; how far each trial slide steps, as
                                   ; a multiple of the text height.
                                   ; Smaller finds narrower gaps and
                                   ; takes proportionally longer

(setq cd:*reach-f* 4.0)            ; how far a text may slide from where
                                   ; it started, each way, as a multiple
                                   ; of its own width.  A text with
                                   ; nothing clear inside this is left
                                   ; alone and reported, not parked

(setq cd:*refine* 5)               ; halvings used to bisect the found
                                   ; spot back toward the original one,
                                   ; so the move is the smallest that
                                   ; still clears.  0 leaves the moves on
                                   ; whole cd:*step-f* boundaries

(setq cd:*rowtol-f* 2.0)           ; how tall a "row" is for reading
                                   ; order, as a multiple of the tallest
                                   ; text in the sweep.  Two dimensions
                                   ; inside one row are ordered left to
                                   ; right instead of by height

(setq cd:*arcsegs* 32)             ; chords a full circle is flattened
                                   ; into before it is tested against a
                                   ; text box; an arc gets its share of
                                   ; them.  More is a closer curve and a
                                   ; slower run

(setq cd:*skip-layers* '("DEFPOINTS"))  ; layers whose entities are not
                                   ; ink: nothing on them is treated as
                                   ; an obstacle.  DEFPOINTS does not
                                   ; plot, so text over it is readable

(setq cd:*obstacle-types*          ; entity types read as ink under the
  '("LINE" "LWPOLYLINE" "POLYLINE" "ARC" "CIRCLE" "TEXT" "MTEXT"))
                                   ; text.  DIMENSION is handled on its
                                   ; own and is not listed here.  An
                                   ; INSERT is deliberately absent: a
                                   ; block's bounding box is mostly
                                   ; empty space, so counting it as ink
                                   ; would move texts that read fine

(setq cd:*dimtxt-default* 0.18)    ; DIMTXT to assume when the style
                                   ; record carries none -- AutoCAD's
                                   ; own out-of-the-box value

;;; -------------------- 2-D vector helpers -----------------------------
;;; Strictly 2-element results; inputs may be 2- or 3-element.

(defun cd:2d (p) (list (car p) (cadr p)))
(defun cd:v- (a b) (mapcar '- (cd:2d a) (cd:2d b)))
(defun cd:v+ (a b) (mapcar '+ (cd:2d a) (cd:2d b)))
(defun cd:v* (v s) (list (* (car v) s) (* (cadr v) s)))
(defun cd:dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))
(defun cd:perp (v) (list (- (cadr v)) (car v)))   ; rotate 90 deg CCW
(defun cd:vlen (v) (sqrt (cd:dot v v)))

;; The unit vector along V, or nil when V has no length to speak of --
;; callers branch on the nil rather than dividing by zero.
(defun cd:unit (v / l)
  (setq v (cd:2d v)
        l (cd:vlen v))
  (if (> l 1e-12) (cd:v* v (/ 1.0 l))))

;; The point S along U from BASE -- one line, but it is the whole idea
;; of a track and it reads better named.
(defun cd:on-track (base u s) (cd:v+ base (cd:v* u s)))

;;; -------------------- convex polygons and the clash test -------------
;;; Everything in the drawing is reduced to one of two shapes: a SEGMENT
;;; (two points) or a BOX (four).  Both are convex polygons, so one
;;; separating-axis test covers every pair -- box against segment, box
;;; against box -- and there is no second overlap routine to disagree
;;; with the first.

;; The four corners of a rectangle CENTRED on C, turned by ANG, W wide
;; along that angle and H tall across it.  Counterclockwise from the
;; bottom-left, which is the order the axis walk below assumes.
(defun cd:box (c ang w h / u v hu hv)
  (setq u  (list (cos ang) (sin ang))
        v  (cd:perp u)
        hu (cd:v* u (* 0.5 w))
        hv (cd:v* v (* 0.5 h))
        c  (cd:2d c))
  (list (cd:v- (cd:v- c hu) hv)
        (cd:v- (cd:v+ c hu) hv)
        (cd:v+ (cd:v+ c hu) hv)
        (cd:v+ (cd:v- c hu) hv)))

;; (minx miny maxx maxy) around POLY -- the cheap reject that runs
;; before the axis walk.  A drawing is mostly entities nowhere near the
;; text being placed, and this is what stops the expensive test being
;; run on all of them.
(defun cd:aabb (poly / xs ys)
  (setq xs (mapcar 'car poly)
        ys (mapcar 'cadr poly))
  (list (apply 'min xs) (apply 'min ys)
        (apply 'max xs) (apply 'max ys)))

;; Do two (minx miny maxx maxy) boxes share any area at all?
(defun cd:aabb-hit-p (a b)
  (not (or (< (caddr a) (car b)) (< (caddr b) (car a))
           (< (cadddr a) (cadr b)) (< (cadddr b) (cadr a)))))

;; (lo hi), POLY projected onto the direction AX.
(defun cd:span (poly ax / lo hi d q)
  (foreach q poly
    (setq d (cd:dot q ax))
    (if (or (null lo) (< d lo)) (setq lo d))
    (if (or (null hi) (> d hi)) (setq hi d)))
  (list lo hi))

;; The outward normals of POLY's edges, zero-length ones dropped.  A
;; two-point polygon -- a segment -- yields the single normal that its
;; own direction gives, which is exactly the third axis a segment
;; against a box needs.
(defun cd:axes (poly / out n i a b ax)
  (setq n (length poly) i 0 out nil)
  (while (< i n)
    (setq a  (nth i poly)
          b  (nth (rem (1+ i) n) poly)
          ax (cd:unit (cd:perp (cd:v- b a))))
    (if ax (setq out (cons ax out)))
    (setq i (1+ i)))
  out)

;; Do two convex polygons overlap?  Separating-axis: they do NOT if any
;; one edge normal of either sees their projections fall apart.  Touching
;; exactly -- one span ending where the other begins -- is not an
;; overlap, which is what lets a box sit flush against a line it has
;; just cleared.
(defun cd:hit-p (pa pb / axes apart sa sb ax)
  (setq axes  (append (cd:axes pa) (cd:axes pb))
        apart nil)
  (while (and axes (not apart))
    (setq ax   (car axes)
          axes (cdr axes)
          sa   (cd:span pa ax)
          sb   (cd:span pb ax))
    (if (or (<= (cadr sa) (car sb)) (<= (cadr sb) (car sa)))
      (setq apart T)))
  (not apart))

;;; -------------------- obstacles --------------------------------------
;;; An OBSTACLE is (OWNER AABB POLY).  OWNER is the index of the
;;; dimension record the ink belongs to, or nil for ink that belongs to
;;; the drawing; a record never has to clear its OWN ink, which is what
;;; keeps a dimension's own dimension line -- the line AutoCAD breaks
;;; around the text -- out of its way.

(defun cd:ob (owner poly) (list owner (cd:aabb poly) poly))

;; Every obstacle in OBS that is not OWNER's own and does overlap POLY.
;; Returns T on the first hit: nothing downstream wants the list.
(defun cd:hits-p (poly obs owner / bb hit o)
  (setq bb (cd:aabb poly) hit nil)
  (while (and obs (not hit))
    (setq o   (car obs)
          obs (cdr obs))
    (if (and (or (null owner) (not (equal (car o) owner)))
             (cd:aabb-hit-p bb (cadr o))
             (cd:hit-p poly (caddr o)))
      (setq hit T)))
  hit)

;;; -------------------- text as a rectangle ----------------------------

;; The glyph count of S: the printable characters it would draw.  A
;; "%%d", "%%c", "%%p" or "%%%" is one glyph written as three
;; characters, so counting characters alone would make every box with
;; a degree sign in it two glyphs too wide.
(defun cd:glyphs (s / i n c n2 out)
  (setq n (strlen s) i 1 out 0)
  (while (<= i n)
    (setq c (substr s i 1))
    (if (and (= c "%") (<= (+ i 2) n) (= (substr s (1+ i) 1) "%"))
      (progn
        (setq n2 (strcase (substr s (+ i 2) 1)))
        (cond
          ;; %%o and %%u are overscore/underscore toggles: three
          ;; characters, no glyph at all
          ((member n2 '("O" "U")) (setq i (+ i 3)))
          ;; the rest of the codes draw one glyph for their three
          ((member n2 '("D" "C" "P" "%")) (setq out (1+ out) i (+ i 3)))
          ;; "%%" in front of anything else is two ordinary per-cent
          ;; signs, which is what the first of them is counted as here
          (T (setq out (1+ out) i (1+ i)))))
      (progn (setq out (1+ out) i (1+ i)))))
  out)

;; S split on MTEXT's "\P" hard line break, as a list of strings.  A
;; string with no break is a one-element list, which is what keeps the
;; two cases one code path.
(defun cd:lines (s / out i)
  (setq out nil)
  (while (setq i (vl-string-search "\\P" s))
    (setq out (cons (substr s 1 i) out)
          s   (substr s (+ i 3))))
  (reverse (cons s out)))

;; (W H) for the string S set at height HGT -- the widest of its lines
;; by cd:*charwidth*, and a height that grows by half a line for each
;; line after the first, the way stacked dimension text does.
(defun cd:text-size (s hgt / ls n w l)
  (setq ls (cd:lines s)
        n  (length ls)
        w  0.0)
  (foreach l ls
    (setq w (max w (* (cd:glyphs l) hgt cd:*charwidth*))))
  (list w (* hgt (- (* 1.5 n) 0.5))))

;; The box for a string whose rectangle is W by H, anchored at ANCHOR
;; with justification (DX DY) -- the offsets from the anchor to the
;; rectangle's lower-left corner -- and turned by ANG about the anchor.
(defun cd:just-box (anchor ang w h dx dy / u v c)
  (setq u (list (cos ang) (sin ang))
        v (cd:perp u)
        c (cd:v+ (cd:2d anchor)
                 (cd:v+ (cd:v* u (+ dx (* 0.5 w)))
                        (cd:v* v (+ dy (* 0.5 h))))))
  (cd:box c ang w h))

;; POLY grown by PAD on every side -- how cd:*gap-f* turns "the ink does
;; not cross the letters" into "the letters are readable".  The box is
;; rebuilt rather than offset edge by edge, which only works because
;; every box here is a rectangle and is always built by cd:box.
(defun cd:grow (c ang w h pad)
  (cd:box c ang (+ w (* 2.0 pad)) (+ h (* 2.0 pad))))

;;; -------------------- reading the drawing ----------------------------

(defun cd:dxf (code ed) (cdr (assoc code ed)))

;; CODE's value off ED, or DFLT when the group is absent or is not a
;; number.  Half the DXF groups read here are optional and AutoCAD omits
;; the ones sitting at their default, so this is the common case, not
;; the defensive one.
(defun cd:num (code ed dflt / v)
  (setq v (cd:dxf code ed))
  (if (numberp v) v dflt))

;; A dimension's own override of dimension variable VAR, out of its
;; xdata: an "ACAD" application list, a (1000 . "DSTYLE") marker, then
;; (1070 . var) / value pairs between braces.  nil when the dimension
;; overrides nothing, which is the usual answer.
(defun cd:override (ed var / xd app rest found on out v k)
  (setq xd (cdr (assoc -3 ed)))
  (foreach app xd
    (if (= (strcase (car app)) "ACAD")
      (progn
        ;; the name is the head of the list and every element after it
        ;; is a group pair, so (car v) below is always a group code --
        ;; which is the test, because a dotted pair is a list to
        ;; AutoLISP and there is nothing else in here to tell it from
        (setq rest  (cdr app)
              found nil
              on    nil)
        (foreach v rest
          (setq k (car v))
          (cond
            ((and (= k 1000) (= (strcase (cdr v)) "DSTYLE")) (setq on T))
            ((not on) nil)
            ((= k 1002) (if (= (cdr v) "}") (setq on nil found nil)))
            ;; a code, then whatever group carries its value
            ((and found (member k '(1040 1070)))
             (setq out (cdr v) found nil))
            ((and (= k 1070) (= (cdr v) var)) (setq found T))
            (T (setq found nil)))))))
  out)

;; The effective text height of the dimension whose entity list is ED
;; and whose style record is STY: DIMTXT times DIMSCALE, with the
;; dimension's own overrides laid over both.  A DIMSCALE of 0 is
;; annotative -- scaled by the viewport, which is not a thing this file
;; can measure -- so the drawing's current DIMSCALE stands in.
;; The DIMSCALE everything the dimension draws is sized by: the style's,
;; the dimension's own override of it where it has one, and -- for the
;; annotative 0, which is scaled by a viewport this file cannot measure
;; -- the drawing's current one.
(defun cd:dimscale (ed sty / scl o)
  (setq scl (cd:num 40 sty 1.0))
  (if (setq o (cd:override ed 40)) (setq scl o))
  (if (<= scl 0.0) (setq scl (cond ((getvar "DIMSCALE")) (1.0))))
  (if (<= scl 0.0) (setq scl 1.0))
  scl)

(defun cd:txt-height (ed sty / txt o)
  (setq txt (cd:num 140 sty cd:*dimtxt-default*))
  (if (setq o (cd:override ed 140)) (setq txt o))
  (* txt (cd:dimscale ed sty)))

;; What the dimension actually says.  Group 1 is the override: empty
;; means "the measurement", and "<>" inside an override stands for the
;; measurement too.  A single space is AutoCAD's "draw no text at all",
;; and it comes back as "".
(defun cd:dim-text (ed / ov meas i)
  (setq ov   (cd:dxf 1 ed)
        meas (cd:dim-meas ed))
  (cond
    ((null ov) meas)
    ((= ov "") meas)
    ((= (vl-string-trim " " ov) "") "")
    ((setq i (vl-string-search "<>" ov))
     (strcat (substr ov 1 i) meas (substr ov (+ i 3))))
    (T ov)))

;; The measurement as the text would read it.  Group 42 is what AutoCAD
;; stored; a linear or aligned dimension is recomputed from its own
;; definition points instead, so a dimension somebody stretched still
;; measures its own geometry.
(defun cd:dim-meas (ed / dtype p13 p14 ang v meas)
  (setq dtype (logand 7 (cd:num 70 ed 0))
        meas  (cd:dxf 42 ed)
        p13   (cd:dxf 13 ed)
        p14   (cd:dxf 14 ed))
  (cond
    ((and (= dtype 1) p13 p14) (rtos (distance (cd:2d p13) (cd:2d p14))))
    ((and (= dtype 0) p13 p14)
     (setq ang (cd:num 50 ed 0.0)
           v   (cd:v- p14 p13))
     (rtos (abs (cd:dot v (list (cos ang) (sin ang))))))
    ((and (member dtype '(2 5)) meas (>= meas 0.0)) (angtos meas))
    ((and meas (>= meas 0.0)) (rtos meas))
    (T "")))

;; T when NAME is a layer this run must not write to.
(defun cd:layer-locked-p (name / ld)
  (setq ld (tblsearch "LAYER" name))
  (and ld (= 4 (logand 4 (cd:num 70 ld 0)))))

;; T when NAME is a layer whose entities are not ink.
(defun cd:layer-skip-p (name / hit l)
  (setq hit nil)
  (foreach l cd:*skip-layers*
    (if (= (strcase l) (strcase name)) (setq hit T)))
  hit)

;;; -------------------- entities reduced to polygons -------------------

;; Every (10 . pt) group on ED, in order -- an LWPOLYLINE's vertices.
(defun cd:pts10 (ed / out g)
  (setq out nil)
  (foreach g ed
    (if (= (car g) 10)
      (setq out (cons (cd:2d (cdr g)) out))))
  (reverse out))

;; PTS as a run of two-point polygons, closed back to the start when
;; CLOSED.  Bulges are read as their chord: a bulged edge's real arc
;; bows AWAY from the chord, so a text the chord clears can still be
;; caught -- the one place this file is optimistic, and it is written
;; down in the README rather than left to be discovered.
(defun cd:chain (pts closed / out rest)
  (setq out nil rest pts)
  (while (cdr rest)
    (setq out  (cons (list (car rest) (cadr rest)) out)
          rest (cdr rest)))
  (if (and closed (cdr pts))
    (setq out (cons (list (last pts) (car pts)) out)))
  out)

;; The arc CENTRE/R from A0 through SWEEP radians, as chords.
(defun cd:arc-chain (centre r a0 sweep / n i out step pts)
  (setq n    (max 2 (fix (+ 0.5 (* cd:*arcsegs* (/ (abs sweep) (* 2.0 pi))))))
        step (/ sweep (float n))
        i    0
        pts  nil)
  (while (<= i n)
    (setq pts (cons (list (+ (car centre) (* r (cos (+ a0 (* i step)))))
                          (+ (cadr centre) (* r (sin (+ a0 (* i step))))))
                    pts)
          i   (1+ i)))
  (setq out (cd:chain (reverse pts) nil))
  out)

;; The polygons a TEXT entity covers: one box, justified the way its
;; 72/73 codes say and anchored where they say to anchor it.  Group 11
;; is the alignment point and only means anything when one of the two
;; is non-zero -- otherwise group 10 is the left end of the baseline.
(defun cd:text-poly (ed / s hgt wh w h ang j72 j73 p10 p11 u anchor dx dy)
  (setq s (cd:dxf 1 ed))
  (if (or (null s) (= s "")) nil
    (progn
      (setq hgt (cd:num 40 ed 1.0)
            wh  (cd:text-size s hgt)
            w   (car wh)
            h   (cadr wh)
            ang (cd:num 50 ed 0.0)
            j72 (cd:num 72 ed 0)
            j73 (cd:num 73 ed 0)
            p10 (cd:dxf 10 ed)
            p11 (cd:dxf 11 ed))
      (cond
        ;; Aligned (3) and Fit (5) are not justifications at all: the
        ;; text is SET BETWEEN groups 10 and 11, so those two ARE its
        ;; ends -- both the width the glyph count worked out and the
        ;; angle group 50 carries are the wrong ones, and reading them
        ;; as an anchor would put the box over one end of the letters
        ((and (member j72 '(3 5)) p10 p11
              (setq u (cd:unit (cd:v- p11 p10))))
         (list (cd:box (cd:v+ (cd:v* (cd:v+ (cd:2d p10) (cd:2d p11)) 0.5)
                              (cd:v* (cd:perp u) (* 0.5 h)))
                       (angle (cd:2d p10) (cd:2d p11))
                       (distance (cd:2d p10) (cd:2d p11))
                       h)))
        ((<= w 0.0) nil)
        (T
         ;; group 11 is the alignment point and only means anything when
         ;; the text is justified away from the left of its own baseline
         (setq anchor (if (and (or (/= 0 j72) (/= 0 j73)) p11) p11 p10))
         (setq dx (cond ((= j72 0) 0.0)
                        ((= j72 2) (- w))
                        (T (* -0.5 w))))       ; centre and middle
         (setq dy (cond ((= j72 4) (* -0.5 h)) ; "middle" is both at once
                        ((= j73 2) (* -0.5 h))
                        ((= j73 3) (- h))
                        (T 0.0)))              ; baseline and bottom
         (if anchor (list (cd:just-box anchor ang w h dx dy))))))))

;; The polygons an MTEXT entity covers: one box, placed by its
;; attachment point (group 71, 1 = top-left counting across then down).
(defun cd:mtext-poly (ed / s hgt wh w h ang ap col row anchor dx dy xdir)
  (setq s (cd:dxf 1 ed))
  (if (or (null s) (= s "")) nil
    (progn
      (setq hgt  (cd:num 40 ed 1.0)
            wh   (cd:text-size s hgt)
            w    (car wh)
            h    (cadr wh)
            xdir (cd:dxf 11 ed)
            ang  (if (and xdir (cd:unit (cd:2d xdir)))
                   (atan (cadr xdir) (car xdir))
                   (cd:num 50 ed 0.0))
            ap   (cd:num 71 ed 1)
            col  (rem (1- ap) 3)
            row  (/ (1- ap) 3))
      (setq anchor (cd:dxf 10 ed))
      (setq dx (cond ((= col 0) 0.0) ((= col 1) (* -0.5 w)) (T (- w))))
      (setq dy (cond ((= row 0) (- h)) ((= row 1) (* -0.5 h)) (T 0.0)))
      (if (and anchor (> w 0.0))
        (list (cd:just-box anchor ang w h dx dy))))))

;; Every polygon EN covers, as ink.  An entity type the file does not
;; know is no ink at all -- listing it in cd:*obstacle-types* is what
;; makes it ink, and a type with no branch here would return nothing
;; anyway.
(defun cd:ent-polys (en / ed typ pts closed centre r a0 a1 sweep)
  (setq ed  (entget en)
        typ (cd:dxf 0 ed))
  (cond
    ((= typ "LINE")
     (list (list (cd:2d (cd:dxf 10 ed)) (cd:2d (cd:dxf 11 ed)))))
    ((= typ "LWPOLYLINE")
     (setq pts    (cd:pts10 ed)
           closed (= 1 (logand 1 (cd:num 70 ed 0))))
     (cd:chain pts closed))
    ((= typ "POLYLINE")
     (setq pts    (cd:vertex-pts en)
           closed (= 1 (logand 1 (cd:num 70 ed 0))))
     (cd:chain pts closed))
    ((= typ "CIRCLE")
     (cd:arc-chain (cd:2d (cd:dxf 10 ed)) (cd:num 40 ed 0.0) 0.0 (* 2.0 pi)))
    ((= typ "ARC")
     (setq centre (cd:2d (cd:dxf 10 ed))
           r      (cd:num 40 ed 0.0)
           a0     (cd:num 50 ed 0.0)
           a1     (cd:num 51 ed 0.0)
           sweep  (rem (+ (- a1 a0) (* 4.0 pi)) (* 2.0 pi)))
     (if (< sweep 1e-9) (setq sweep (* 2.0 pi)))
     (cd:arc-chain centre r a0 sweep))
    ((= typ "TEXT") (cd:text-poly ed))
    ((= typ "MTEXT") (cd:mtext-poly ed))
    (T nil)))

;; The vertices of an old-style heavy POLYLINE: the VERTEX entities that
;; follow it, up to its SEQEND.  They are subentities, so no ssget ever
;; hands one over and the walk has to be made here.
(defun cd:vertex-pts (en / e ed typ out p)
  (setq out nil e (entnext en))
  (while (and e (setq ed (entget e))
              (/= (setq typ (cd:dxf 0 ed)) "SEQEND"))
    (if (and (= typ "VERTEX") (setq p (cd:dxf 10 ed)))
      (setq out (cons (cd:2d p) out)))
    (setq e (entnext e)))
  (reverse out))

;;; -------------------- the dimension record ---------------------------
;;; One per DIMENSION in the sweep.  Positional, with an accessor each,
;;; because every field is read from three or four places and (nth 7 r)
;;; at each of them is how a field quietly becomes the wrong field.

(defun cd:rec (idx en dtype base u s0 off ang w h own why)
  (list idx en dtype base u s0 off ang w h own why))

(defun cd:r-idx  (r) (nth 0 r))    ; also the obstacle OWNER tag
(defun cd:r-en   (r) (nth 1 r))
(defun cd:r-type (r) (nth 2 r))    ; DXF 70's low three bits
(defun cd:r-base (r) (nth 3 r))    ; a point on the dimension line
(defun cd:r-u    (r) (nth 4 r))    ; the unit vector along it: the TRACK
(defun cd:r-s0   (r) (nth 5 r))    ; where the text sits on the track now
(defun cd:r-off  (r) (nth 6 r))    ; the across-the-track offset, kept
(defun cd:r-ang  (r) (nth 7 r))    ; the angle the text itself is set at
(defun cd:r-w    (r) (nth 8 r))
(defun cd:r-h    (r) (nth 9 r))
(defun cd:r-own  (r) (nth 10 r))   ; (dimline ext1 ext2), dim line FIRST
(defun cd:r-why  (r) (nth 11 r))   ; nil, or why it cannot slide

;; The text box of R with its text slid to S along the track, grown by
;; cd:*gap-f* so "clear" means readable rather than merely not crossed.
(defun cd:r-box (r s / centre pad)
  (setq centre (cd:v+ (cd:on-track (cd:r-base r) (cd:r-u r) s) (cd:r-off r))
        pad    (* cd:*gap-f* (cd:r-h r)))
  (cd:grow centre (cd:r-ang r) (cd:r-w r) (cd:r-h r) pad))

;; The kind of dimension DTYPE is, in the words the report uses.
(defun cd:typename (dtype)
  (cond ((member dtype '(2 5)) "angular")
        ((= dtype 3) "diameter")
        ((= dtype 4) "radius")
        ((= dtype 6) "ordinate")
        (T "linear")))

;; The record for one DIMENSION.  Returns nil only for an entity that
;; is not a dimension at all; everything else comes back as a record,
;; with cd:r-why saying why it will not be moved when it will not.
(defun cd:read-dim (idx en / ed dtype sty hgt s wh w h p10 p11 p13 p14
                        ang u base s0 off s13 s14 f13 f14 exe own why txtang)
  (setq ed (entget en))
  ;; an entity that is not a dimension, and an ename that no longer
  ;; names one, both come back nil rather than half a record
  (if (and ed (= (cd:dxf 0 ed) "DIMENSION"))
    (progn
      (setq dtype (logand 7 (cd:num 70 ed 0))
            sty   (tblsearch "DIMSTYLE" (cond ((cd:dxf 3 ed)) ("STANDARD")))
            hgt   (cd:txt-height ed sty)
            s     (cd:dim-text ed)
            wh    (cd:text-size s hgt)
            w     (car wh)
            h     (cadr wh)
            p10   (cd:dxf 10 ed)
            p11   (cd:dxf 11 ed)
            p13   (cd:dxf 13 ed)
            p14   (cd:dxf 14 ed))
      ;; the track: the direction of the dimension line, which is group
      ;; 50 on a rotated dimension and the run between the two extension
      ;; line origins on an aligned one
      (setq ang (if (= dtype 1)
                  (if (and p13 p14) (angle (cd:2d p13) (cd:2d p14)) 0.0)
                  (cd:num 50 ed 0.0))
            u   (list (cos ang) (sin ang)))
      ;; the text reads along the dimension line unless the style turns
      ;; it upright (DIMTIH), and group 53 turns it further either way
      (setq txtang (+ (if (and sty (/= 0 (cd:num 73 sty 0))) 0.0 ang)
                      (cd:num 53 ed 0.0)))
      (setq base (if p10 (cd:2d p10) '(0.0 0.0)))
      ;; where the text is now, split into along-track and across-track:
      ;; only the first of the two is ever written back
      (if (null p11)
        ;; no stored text point: AutoCAD's default, the middle of the
        ;; dimension line with the text sitting a gap above it
        (setq p11 (cd:v+ base
                         (cd:v+ (cd:v* u (if (and p13 p14)
                                           (* 0.5 (+ (cd:dot (cd:v- p13 base) u)
                                                     (cd:dot (cd:v- p14 base) u)))
                                           0.0))
                                (cd:v* (cd:perp u) (* 0.5 h))))))
      (setq s0  (cd:dot (cd:v- p11 base) u)
            off (cd:v- (cd:v- p11 base) (cd:v* u s0)))
      ;; the ink this dimension itself draws: the dimension line first
      ;; -- the one thing it never has to clear -- then the two
      ;; extension lines, which cross its track and which it does
      (setq own nil)
      (if (and p13 p14)
        (progn
          (setq exe (* (cd:num 44 sty 0.18) (cd:dimscale ed sty))
                s13 (cd:dot (cd:v- p13 base) u)
                s14 (cd:dot (cd:v- p14 base) u)
                f13 (cd:on-track base u s13)
                f14 (cd:on-track base u s14))
          (setq own (list (list f13 f14)
                          (list (cd:2d p13) (cd:v+ f13 (cd:ext-tip p13 f13 exe)))
                          (list (cd:2d p14) (cd:v+ f14 (cd:ext-tip p14 f14 exe)))))))
      (setq why (cond ((not (member dtype '(0 1))) 'curve)
                      ((<= w 0.0) 'notext)
                      ((cd:layer-locked-p (cond ((cd:dxf 8 ed)) ("0"))) 'locked)))
      (cd:rec idx en dtype base u s0 off txtang w h own why))))

;; How far an extension line runs PAST the dimension line: DIMEXE along
;; the direction it was already going.  A zero-length run -- the
;; definition point sitting on the dimension line -- gets no tip rather
;; than a division by zero.
(defun cd:ext-tip (org foot exe / v)
  (setq v (cd:unit (cd:v- foot org)))
  (if v (cd:v* v exe) '(0.0 0.0)))

;;; -------------------- the search -------------------------------------

;; The nearest S to R's current spot at which its text box clears OBS --
;; the current spot itself when that is already clear.  Stepped outward
;; in cd:*step-f* steps to cd:*reach-f*, then bisected back toward where
;; it started so the move is the smallest one that still works.  nil
;; when nothing inside reach is clear: the caller leaves the text alone
;; and says so, which is worth more to a drafter than a text parked in
;; an arbitrary spot.
(defun cd:find-slide (r obs smid / s0 step reach owner k s found blocked
                          dirs d lo hi mid i)
  (setq s0    (cd:r-s0 r)
        owner (cd:r-idx r)
        step  (max 1e-6 (* cd:*step-f* (cd:r-h r)))
        reach (* cd:*reach-f* (cd:r-w r)))
  (if (not (cd:hits-p (cd:r-box r s0) obs owner))
    s0
    (progn
      ;; the way back toward the middle of its own dimension line is
      ;; tried first, because the middle is where a dimension's text
      ;; belongs; a text already AT the middle has no way back, and its
      ;; tie goes down the line rather than up it
      (setq dirs (if (< s0 smid) '(1.0 -1.0) '(-1.0 1.0)))
      (setq k 1 found nil blocked nil)
      (while (and (not found) (<= (* k step) reach))
        (foreach d dirs
          (if (not found)
            (progn
              (setq s (+ s0 (* d k step)))
              (if (not (cd:hits-p (cd:r-box r s) obs owner))
                (setq found   s
                      blocked (+ s0 (* d (1- k) step)))))))
        (setq k (1+ k)))
      (if (and found (> cd:*refine* 0))
        (progn
          (setq lo blocked hi found i 0)
          (while (< i cd:*refine*)
            (setq mid (* 0.5 (+ lo hi)))
            (if (cd:hits-p (cd:r-box r mid) obs owner)
              (setq lo mid)
              (setq hi mid))
            (setq i (1+ i)))
          (setq found hi)))
      found)))

;; The middle of R's own dimension line on its own track -- where the
;; text would sit if nothing were in the way.  Its current spot when
;; the dimension has no extension line origins to take a middle from.
(defun cd:home (r / own)
  (setq own (cd:r-own r))
  (if own
    (* 0.5 (+ (cd:dot (cd:v- (caar own) (cd:r-base r)) (cd:r-u r))
              (cd:dot (cd:v- (cadar own) (cd:r-base r)) (cd:r-u r))))
    (cd:r-s0 r)))

;;; -------------------- reading order ----------------------------------

;; Row index of R, counting down the sheet: rows ROWTOL tall, so two
;; dimensions within one row sort left to right rather than by a
;; hairsbreadth of height.
(defun cd:row (r rowtol)
  (fix (/ (cadr (cd:v+ (cd:on-track (cd:r-base r) (cd:r-u r) (cd:r-s0 r))
                       (cd:r-off r)))
          rowtol)))

;; Reading order, as a comparator: down the sheet, then left to right,
;; then by index so no two records ever compare equal.  vl-sort DROPS
;; what compares equal to its predecessor, so a comparator that can
;; return "same" for two different dimensions loses one of them.
(defun cd:order-lt (a b / ra rb xa xb)
  (setq ra (cd:row a cd:*rowtol*)
        rb (cd:row b cd:*rowtol*))
  (cond
    ((/= ra rb) (> ra rb))
    (T
     (setq xa (car (cd:v+ (cd:on-track (cd:r-base a) (cd:r-u a) (cd:r-s0 a))
                          (cd:r-off a)))
           xb (car (cd:v+ (cd:on-track (cd:r-base b) (cd:r-u b) (cd:r-s0 b))
                          (cd:r-off b))))
     (cond ((/= xa xb) (< xa xb))
           (T (< (cd:r-idx a) (cd:r-idx b)))))))

;; cd:*rowtol* is not a knob: it is cd:*rowtol-f* measured against the
;; sweep that is actually in front of us, and it is a global only
;; because vl-sort's comparator takes two arguments and no more.
(setq cd:*rowtol* 1.0)

(defun cd:set-rowtol (recs / h r)
  (setq h 0.0)
  (foreach r recs (setq h (max h (cd:r-h r))))
  (setq cd:*rowtol* (max 1e-6 (* cd:*rowtol-f* h))))

;;; -------------------- the plan ---------------------------------------
;;; The result for one dimension is (REC S MOVED CLEARED):
;;;   S        where its text ends up on the track
;;;   MOVED    T when that is not where it started
;;;   CLEARED  T when the box there is clear of everything placed

;; Results back in the order the records came in.  No two records
;; share an index, so nothing here ever compares equal -- vl-sort DROPS
;; what does.
(defun cd:res-lt (x y)
  (< (cd:r-idx (cd:res-rec x)) (cd:r-idx (cd:res-rec y))))

(defun cd:res-rec  (x) (nth 0 x))
(defun cd:res-s    (x) (nth 1 x))
(defun cd:res-moved (x) (nth 2 x))
(defun cd:res-clear (x) (nth 3 x))

;; Everything in the drawing that is ink, as obstacles: the entities in
;; SS that are not dimensions, plus what every dimension in RECS draws
;; for itself.  A dimension's own dimension line is tagged with its
;; index so that dimension alone ignores it; the extension lines are
;; tagged nil, because a text over one of those is unreadable whoever
;; drew it.
(defun cd:static-obs (ss recs / out i n en ed typ lay own first p r)
  (setq out nil i 0 n (if ss (sslength ss) 0))
  (while (< i n)
    (setq en  (ssname ss i)
          ed  (entget en)
          typ (cd:dxf 0 ed)
          lay (cond ((cd:dxf 8 ed)) ("0")))
    (if (and (member typ cd:*obstacle-types*) (not (cd:layer-skip-p lay)))
      (foreach p (cd:ent-polys en)
        (setq out (cons (cd:ob nil p) out))))
    (setq i (1+ i)))
  (foreach r recs
    (setq own   (cd:r-own r)
          first T)
    (foreach p own
      (setq out   (cons (cd:ob (if first (cd:r-idx r) nil) p) out)
            first nil)))
  out)

;; The three buckets, in the order they get to claim a spot: what cannot
;; move, then what is already clear of everything fixed, then the rest.
;; Each is in reading order inside itself.  This is the whole of the
;; policy -- a text that is already good keeps its spot and the ones
;; that are not go around it.
(defun cd:buckets (recs static / fixed clear dirty r)
  (setq fixed nil clear nil dirty nil)
  (foreach r recs
    (cond
      ((cd:r-why r) (setq fixed (cons r fixed)))
      ((not (cd:hits-p (cd:r-box r (cd:r-s0 r)) static (cd:r-idx r)))
       (setq clear (cons r clear)))
      (T (setq dirty (cons r dirty)))))
  (list (vl-sort (reverse fixed) 'cd:order-lt)
        (vl-sort (reverse clear) 'cd:order-lt)
        (vl-sort (reverse dirty) 'cd:order-lt)))

;; What CLEARDIM would do to RECS, given the drawing's own ink STATIC:
;; one result per record, in the records' own order.  Pure -- it reads
;; the drawing through what it was handed and writes nothing -- so the
;; policy can be tested without a drawing to write to.
(defun cd:plan (recs static / bk order obs out r s res)
  (cd:set-rowtol recs)
  (setq bk    (cd:buckets recs static)
        order (append (car bk) (cadr bk) (caddr bk))
        obs   static
        out   nil)
  (foreach r order
    (setq s (if (cd:r-why r)
              (cd:r-s0 r)                 ; cannot move: it keeps its spot
              (cd:find-slide r obs (cd:home r))))
    (if (null s) (setq s (cd:r-s0 r)))    ; nowhere clear: left as drawn
    (setq res (list r s
                    (> (abs (- s (cd:r-s0 r))) 1e-9)
                    (or (<= (cd:r-w r) 0.0)
                        (not (cd:hits-p (cd:r-box r s) obs (cd:r-idx r))))))
    ;; the spot it just took is ink for everyone after it -- unless there
    ;; are no letters there to be ink.  A dimension whose text is
    ;; suppressed has a text POINT like any other, and counting it would
    ;; put a small square of nothing in the way of the next text along
    (if (> (cd:r-w r) 0.0)
      (setq obs (cons (cd:ob (cd:r-idx r) (cd:r-box r s)) obs)))
    (setq out (cons res out)))
  ;; back into the records' own order, so a caller can pair results with
  ;; the list it handed in without carrying the bucket order around
  (vl-sort out 'cd:res-lt))

;;; -------------------- writing it back --------------------------------

;; Slide RES's text to where the plan put it: group 11, and the bit in
;; group 70 that tells AutoCAD the text sits where it was put rather
;; than where the style would have put it.  Only the along-track part
;; of group 11 changes -- the across-track offset is added back exactly
;; as it was read -- so the text comes out on the same track it went in
;; on.  T when the drawing changed.
(defun cd:apply (res / r ed p flags)
  (setq r (cd:res-rec res))
  (if (not (cd:res-moved res))
    nil
    (progn
      (setq ed    (entget (cd:r-en r))
            p     (cd:v+ (cd:on-track (cd:r-base r) (cd:r-u r) (cd:res-s res))
                         (cd:r-off r))
            flags (cd:num 70 ed 0))
      (setq ed (if (assoc 11 ed)
                 (subst (cons 11 (list (car p) (cadr p) 0.0)) (assoc 11 ed) ed)
                 (append ed (list (cons 11 (list (car p) (cadr p) 0.0))))))
      (setq ed (if (assoc 70 ed)
                 (subst (cons 70 (logior 128 flags)) (assoc 70 ed) ed)
                 (append ed (list (cons 70 (logior 128 flags))))))
      (entmod ed)
      (entupd (cd:r-en r))
      T)))

;;; -------------------- the report -------------------------------------

(defun cd:plural (n one many)
  (strcat (itoa n) " " (if (= n 1) one many)))

;; One line per dimension the run has something to say about, then the
;; totals, under the name WHAT of the command that asked for them.
;; MOVING is T for the run that writes and nil for the scan, so the same
;; report reads correctly either way.
(defun cd:report (what results moving / nmove nstuck nclear skip r why d res)
  (setq nmove 0 nstuck 0 nclear 0 skip nil)
  (foreach res results
    (setq r   (cd:res-rec res)
          why (cd:r-why r))
    (if why
      (progn
        (setq skip (cons why skip))
        (if (not (cd:res-clear res))
          (princ (strcat "\n  " (cd:handle-of r) ": "
                         (cd:why-text why)
                         " - left as drawn, and its text is not clear."))))
      (cond
        ((cd:res-moved res)
         (setq nmove (1+ nmove)
               d     (- (cd:res-s res) (cd:r-s0 r)))
         (princ (strcat "\n  " (cd:handle-of r) ": "
                        (if moving "slid " "would slide ")
                        (rtos (abs d)) " "
                        (if (< d 0.0) "back along" "along")
                        " its dimension line.")))
        ((not (cd:res-clear res))
         (setq nstuck (1+ nstuck))
         (princ (strcat "\n  " (cd:handle-of r)
                        ": nothing within reach of its track is clear"
                        " - left as drawn.")))
        (T (setq nclear (1+ nclear))))))
  (princ (strcat "\n" what ": "
                 (cd:plural (length results) "dimension" "dimensions") "."))
  (princ (strcat "\n  " (itoa nclear) " already clear - left alone."))
  (princ (strcat "\n  "
                 (if moving
                   (cd:plural nmove "slid clear along its own dimension line"
                              "slid clear along their own dimension lines")
                   (cd:plural nmove "to slide clear along its own dimension line"
                              "to slide clear along their own dimension lines"))
                 "."))
  (if (> nstuck 0)
    (princ (strcat "\n  " (itoa nstuck) " with nowhere clear on the track"
                   " - left as drawn.")))
  (if skip (princ (strcat "\n  " (cd:skip-text skip))))
  (list nclear nmove nstuck (length skip)))

;; The handle, which is what a drafter types at SELECT to find the thing
;; the report is talking about.  A record with no entity behind it --
;; cd:plan is pure and can be driven from built records -- falls back to
;; naming the kind, so the report never crashes on the way out.
(defun cd:handle-of (r / ed)
  (if (cd:r-en r) (setq ed (entget (cd:r-en r))))
  (cond ((and ed (cd:dxf 5 ed)) (strcat "handle " (cd:dxf 5 ed)))
        (T (strcat (cd:typename (cd:r-type r)) " dimension"))))

(defun cd:why-text (why)
  (cond ((eq why 'curve) "its track is not a straight dimension line")
        ((eq why 'locked) "its layer is locked")
        (T "it has no text")))

;; "3 skipped: 2 angular tracks, 1 locked layer." -- counted by reason,
;; because "3 skipped" alone tells a drafter nothing they can act on.
(defun cd:skip-text (skip / nc nl nt out w)
  (setq nc 0 nl 0 nt 0 out nil)
  (foreach w skip
    (cond ((eq w 'curve) (setq nc (1+ nc)))
          ((eq w 'locked) (setq nl (1+ nl)))
          (T (setq nt (1+ nt)))))
  (if (> nc 0)
    (setq out (cons (strcat (itoa nc) " on a track that is not a straight"
                            " dimension line") out)))
  (if (> nl 0)
    (setq out (cons (if (= nl 1) "1 on a locked layer"
                      (strcat (itoa nl) " on locked layers")) out)))
  (if (> nt 0)
    (setq out (cons (strcat (itoa nt) " with no text") out)))
  (strcat (itoa (length skip)) " skipped: "
          (cd:join (reverse out) ", ") "."))

(defun cd:join (items sep / out s)
  (setq out "")
  (foreach s items
    (setq out (if (= out "") s (strcat out sep s))))
  out)

;;; -------------------- asking -----------------------------------------

;; The one question either command puts: which part of the drawing to
;; work on.  Enter takes the whole of model space, which is the answer
;; nearly every run wants; a selection is for a sheet with more than one
;; drawing on it.  Returns the selection set, or nil when the drawing
;; holds no dimension at all.
(defun cd:asksel (what / msg ss)
  ;; whatever the drafter had already picked before typing the command
  (setq ss (ssget "_I"))
  (if lzd:watch (lzd:watch ss) ss)
  (if (null ss)
    (progn
      (setq msg (strcat "\nHighlight the drawing to " what
                        " (Enter = whole drawing): "))
      (prompt msg)
      (setq ss (ssget))
      (if lzd:watch (lzd:watch ss) ss)
      (if lzd:ask (lzd:ask msg ss))))
  ;; Enter: everything in the space the drafter is looking at.  CTAB is
  ;; "Model" in model space and the layout's name in a layout, so a run
  ;; started on a sheet does not drag model-space geometry in as ink --
  ;; and a drawing whose entities carry no space group at all still
  ;; answers the plain sweep underneath
  (if (null ss)
    (progn
      (setq ss (ssget "_X"
                      (list (cons 410 (cond ((getvar "CTAB")) ("Model"))))))
      (if lzd:watch (lzd:watch ss) ss)))
  (if (null ss)
    (progn
      (setq ss (ssget "_X"))
      (if lzd:watch (lzd:watch ss) ss)))
  ss)

;; Every record for the dimensions in SS, indexed in the order ssget
;; hands them over -- which is the order the obstacle owner tags and the
;; final result order are both in.
(defun cd:records (ss / out i n en r)
  (setq out nil i 0 n (if ss (sslength ss) 0))
  (while (< i n)
    (setq en (ssname ss i))
    (if (= (cd:dxf 0 (entget en)) "DIMENSION")
      (if (setq r (cd:read-dim (length out) en))
        (setq out (cons r out))))
    (setq i (1+ i)))
  (reverse out))

;;; -------------------- the commands -----------------------------------

;; The sysvars either command changes, in the order they come back --
;; OSMODE first, because object snaps are the setting a drafter misses
;; most if a run is ever cut short partway.
(defun cd:sysvars () '("OSMODE" "CMDECHO"))

(defun cd:syssave (vars / v)
  (foreach v vars
    (if (and (not (assoc v cd:*sysold*))
             (/= nil (getvar v)))
        (setq cd:*sysold*
              (append cd:*sysold* (list (cons v (getvar v))))))))

(defun cd:sysrestore ( / p)
  (foreach p cd:*sysold* (setvar (car p) (cdr p)))
  (setq cd:*sysold* nil))

(defun c:CLEARDIM ( / *error* undo-open ss recs static results n res)
  (defun *error* (msg)
    ;; user settings come back FIRST so nothing below can skip them
    (cd:sysrestore)
    ;; command-s, never plain command: 2015+ engines reject (command)
    ;; inside *error* unless the error mode was pushed beforehand
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (setq undo-open nil)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nCLEARDIM error: " msg)))
    (if lzd:report (lzd:report "CLEARDIM" *cleardim-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "CLEARDIM" *cleardim-version*))
  (cd:syssave (cd:sysvars))
  (setvar "CMDECHO" 0)
  (setq ss (cd:asksel "CLEARDIM"))
  (setq recs (cd:records ss))
  (if (null recs)
    (princ "\nCLEARDIM: no dimensions in the selection - nothing to do.")
    (progn
      ;; opened only when undo is recording: _Begin in a drawing whose
      ;; UNDOCTL has bit 1 clear errors out of the command
      (if (= 1 (logand 1 (getvar "UNDOCTL")))
        (progn
          (command "_.UNDO" "_Begin")
          (setq undo-open T)))
      (setq static  (cd:static-obs ss recs)
            results (cd:plan recs static)
            n       0)
      (foreach res results (if (cd:apply res) (setq n (1+ n))))
      (cd:report "CLEARDIM" results T)
      (if (> n 0)
        (princ "\n  One U puts every one of them back."))
      (if undo-open
        (progn
          (command "_.UNDO" "_End")
          (setq undo-open nil)))))
  (cd:sysrestore)
  (princ))

(defun c:CLEARDIMSCAN ( / *error* ss recs static results)
  (defun *error* (msg)
    (cd:sysrestore)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nCLEARDIMSCAN error: " msg)))
    (if lzd:report (lzd:report "CLEARDIMSCAN" *cleardim-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "CLEARDIMSCAN" *cleardim-version*))
  (cd:syssave (cd:sysvars))
  (setvar "CMDECHO" 0)
  (setq ss (cd:asksel "CLEARDIMSCAN"))
  (setq recs (cd:records ss))
  (if (null recs)
    (princ "\nCLEARDIMSCAN: no dimensions in the selection - nothing to do.")
    (progn
      (setq static  (cd:static-obs ss recs)
            results (cd:plan recs static))
      (cd:report "CLEARDIMSCAN" results nil)
      (princ "\n  Nothing was moved - run CLEARDIM to do it.")))
  (cd:sysrestore)
  (princ))

(defun c:CLEARDIMVER ()
  (princ (strcat "\nCLEARDIM " *cleardim-version*))
  (princ))

;; Quiet inside the whole build: LAZPASS.lsp and CALOFIN-LOADER.lsp set
;; the flag while they load their members.  APPLOADed alone the flag is
;; nil and this prints, which is the one time somebody wants to be told.
;; CALVER reports the whole roster whenever it is asked.
(if (not *calofin-quiet*)
  (princ (strcat "\nCLEARDIM " *cleardim-version*
                 " loaded. Commands: CLEARDIM (slide crowded dimension"
                 " text clear along its own dimension line),"
                 " CLEARDIMSCAN (say what it would do, change nothing).")))
(princ)
