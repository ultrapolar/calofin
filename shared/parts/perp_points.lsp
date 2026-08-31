;;; perp_points.lsp  --  AutoCAD 2018 (AutoLISP)
;;;
;;; Command: PERPPTS
;;;
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;
;;; Splits a selected line into N equally-spaced points (both endpoints
;;; included), then for each division point creates a new point offset
;;; perpendicular to the line by a user-supplied length.  The new points
;;; are joined with a polyline -- straight segments, arcs, or a mix of
;;; the two -- and an aligned dimension is drawn from each new point
;;; back to its base point on the line.
;;;
;;; The routine then offers to REPEAT on the polyline it just created:
;;; you are asked again for a number of points, which are spaced equally
;;; ALONG the new polyline; each is offset by a user length to build the
;;; next polyline.  The offset direction -- and therefore every dimension
;;; -- stays perpendicular to the ORIGINAL line, not to the new polyline,
;;; so all offsets accumulate in one consistent direction.  Repeat as
;;; many times as you like.
;;;
;;; Workflow
;;;   1. Select a LINE (a polyline is also accepted, so work started in
;;;      an earlier session can be resumed).
;;;   2. Say whether the overall width has changed: Grew, Shrank, New
;;;      or Unchanged.  The width meant is the distance straight across,
;;;      end to end, not the length of the object; half of any
;;;      difference is added to (or taken off) each end, and the line in
;;;      the drawing is resized to match.
;;;   3. Click a point to set the direction:
;;;        - the line end nearest the click becomes START, the far end
;;;          FINISH, fixing the order the lengths are entered in;
;;;        - the side of the line the click lands on is the side the new
;;;          points are offset toward.
;;;   4. Enter how many values (points) are required  (>= 2).
;;;   5. Enter a length for each point, in order START -> FINISH.
;;;      Press Enter to reuse the previous length when it repeats, or
;;;      type B (Back) to step back and re-enter the previous point
;;;      (U, the old keyword, is still accepted).
;;;   6. Say how the points are joined: Straight (every segment a
;;;      line, which is what the routine has always drawn), Arcs (every
;;;      segment an arc), or Mixed, which then asks which segment
;;;      numbers are arcs -- "1 3-5" -- and leaves the rest straight.
;;;      The question is only asked once there are three points or
;;;      more, and the answer becomes the default for the next round.
;;;   7. Choose whether to repeat on the new polyline.  If so, enter a
;;;      new point count and repeat from step 5 with the new polyline as
;;;      the path.
;;;   8. Pick the dimension style, STANDARD INCHES or SIDE STANDARD.
;;;      Every dimension is then drawn at once, on the DIMENSIONS layer.
;;;
;;; The offset side is fixed once from the direction click in step 3 and
;;; reused for every round, so all offsets stay on the same side of the
;;; original line and every dimension stays perpendicular to it.
;;;
;;; The overall width
;;;   Walls get re-measured, and the number that comes back is the
;;;   distance straight across, end to end.  That is what step 2 asks
;;;   for -- never the developed length of the OBJECT, which on anything
;;;   bowed runs further than the width it spans.  Grew and Shrank take
;;;   the difference, New takes the width itself, and Unchanged (the
;;;   default, and Enter) leaves everything exactly as it was.
;;;
;;;   A new width is made true by scaling the selected object about the
;;;   midpoint of its two ends, so exactly half the difference lands at
;;;   each end and the shape between them is carried along.  The object
;;;   in the drawing is resized too, not just the numbers behind it: the
;;;   offsets and their dimensions are measured off it, so leaving it at
;;;   the old width would put every base point somewhere the drawing
;;;   says nothing is.  The base points and dimensions then follow the
;;;   resized object, since they are spaced along it after the resize.
;;;   The whole thing sits inside the command's undo group, so one U
;;;   puts the width back.
;;;
;;; Straight lines, arcs, or both
;;;   A measured wall is rarely all one or all the other: a radiused
;;;   stretch reads as an arc, a straight run reads as a line, and one
;;;   profile often needs both -- which is why step 5 asks instead of
;;;   assuming.  An arc segment is a bulge written onto the same
;;;   LWPOLYLINE, so whatever the answer the round produces one
;;;   editable polyline through the measured points: never a spline and
;;;   never a curve-fit heavy polyline.  Every point takes a direction
;;;   from the circle through it and its two neighbours, and a segment
;;;   is bent to the angle its two ends agree on, so points taken off a
;;;   real radius come back as that radius and every arc still passes
;;;   exactly through the two points it joins.
;;;   Once a round has drawn arcs, the next round spaces its base
;;;   points along the drawn curve rather than along the chords -- the
;;;   arcs bow away from their chords, so chord spacing would put the
;;;   base points off the polyline they are dimensioned from.
;;;
;;; Properties
;;;   * The offset polylines take the layer, colour, linetype, lineweight
;;;     and linetype scale of the object they were offset from.
;;;   * The dimensions go on the DIMENSIONS layer (created if missing)
;;;     and use the dimension style picked in step 6 when the drawing
;;;     has it; otherwise the current style is used and a note is
;;;     printed.
;;;
;;; Robustness
;;;   * The whole run is one UNDO group: a single U reverses everything.
;;;   * Esc or an error at any prompt restores every system variable it
;;;     changed (OSMODE, CMDECHO, PDMODE, CLAYER, the CE* creation
;;;     defaults and the current dimension style), erases the temporary
;;;     guides and closes the UNDO group.
;;;   * Bad input re-prompts instead of aborting the command; zero and
;;;     negative lengths are rejected, as is a direction click that lands
;;;     on the line itself (where "which side" would be ambiguous).
;;;   * All geometry is handled in the current UCS, so the command works
;;;     in a rotated or shifted UCS.
;;;
;;; License: GPL-3.0-or-later
;;; ---------------------------------------------------------------------

(vl-load-com)

;; Version banner: tools/release_lisp.py reads it to stamp the dated
;; REV twin in releases/ (vN.M -> _MMDDYY_REVNM).
(setq *perp-version* "v0.6")

;; --- geometry helpers ------------------------------------------------

;; linear interpolation between two 3D points at parameter tt (0..1)
(defun perp:lerp (a b tt)
  (list (+ (car a)   (* tt (- (car b)   (car a))))
        (+ (cadr a)  (* tt (- (cadr b)  (cadr a))))
        (+ (caddr a) (* tt (- (caddr b) (caddr a))))))

;; total length of a polyline given as a list of points
(defun perp:pathlen (pts / total i)
  (setq total 0.0 i 0)
  (while (< (1+ i) (length pts))
    (setq total (+ total (distance (nth i pts) (nth (1+ i) pts)))
          i     (1+ i)))
  total)

;; point at arc-length distance d along the polyline pts
(defun perp:pt-at (pts d / i a b segd res)
  (cond
    ((<= d 0.0) (car pts))
    (t
     (setq i 0 res nil)
     (while (and (null res) (< (1+ i) (length pts)))
       (setq a    (nth i pts)
             b    (nth (1+ i) pts)
             segd (distance a b))
       (if (<= d segd)
         (setq res (perp:lerp a b (if (> segd 1e-12) (/ d segd) 0.0)))
         (setq d (- d segd) i (1+ i))))
     (if res res (last pts)))))

;; n points equally spaced by arc length along the polyline pts
;; (both endpoints included)
(defun perp:sample (pts n / total i out)
  (setq total (perp:pathlen pts) out '() i 0)
  (while (< i n)
    (setq out (cons (perp:pt-at pts
                                (if (> n 1)
                                  (* (/ (float i) (float (1- n))) total)
                                  0.0))
                    out)
          i   (1+ i)))
  (reverse out))

;; drop consecutive duplicate points (a polyline may carry them)
(defun perp:dedupe (pts / out)
  (setq out (list (car pts)))
  (foreach p (cdr pts)
    (if (> (distance p (car out)) 1e-10)
      (setq out (cons p out))))
  (reverse out))

;; vertices of a LINE / LWPOLYLINE / POLYLINE, in the current UCS.
;; Returns nil for anything else.
(defun perp:verts (e / d et el pts sub sd flg)
  (setq d  (entget e)
        et (cdr (assoc 0 d)))
  (cond
    ;; LINE group 10/11 are WCS
    ((= et "LINE")
     (list (trans (cdr (assoc 10 d)) 0 1)
           (trans (cdr (assoc 11 d)) 0 1)))
    ;; LWPOLYLINE group 10 are OCS 2D points at elevation 38
    ((= et "LWPOLYLINE")
     (setq el  (cond ((cdr (assoc 38 d))) (0.0))
           pts '())
     (foreach x d
       (if (= 10 (car x))
         (setq pts (cons (trans (list (cadr x) (caddr x) el) e 1) pts))))
     (reverse pts))
    ;; heavy POLYLINE: walk the VERTEX entities, OCS points
    ((= et "POLYLINE")
     (setq pts '() sub (entnext e))
     (while (and sub
                 (setq sd (entget sub))
                 (/= "SEQEND" (cdr (assoc 0 sd))))
       (setq flg (cond ((cdr (assoc 70 sd))) (0)))
       ;; skip spline-frame control points and mesh vertices
       (if (and (= "VERTEX" (cdr (assoc 0 sd)))
                (zerop (logand 16 flg))
                (zerop (logand 64 flg)))
         (setq pts (cons (trans (cdr (assoc 10 sd)) e 1) pts)))
       (setq sub (entnext sub)))
     (reverse pts))
    (t nil)))

;; colour of an entity as a CECOLOR string ("BYLAYER", "3", "12,34,56")
(defun perp:color (d / c tc)
  (cond
    ;; 24-bit true colour packed into one integer
    ((setq tc (cdr (assoc 420 d)))
     (strcat (itoa (logand (lsh tc -16) 255)) ","
             (itoa (logand (lsh tc -8) 255)) ","
             (itoa (logand tc 255))))
    ((setq c (cdr (assoc 62 d)))
     (cond ((= c 0) "BYBLOCK")
           ((= c 256) "BYLAYER")
           ;; a negative index means the layer is off; the colour still applies
           (t (itoa (abs c)))))
    (t "BYLAYER")))

;; --- arcs through the points -----------------------------------------
;; Straight segments need nothing: PLINE already draws them.  An arc
;; segment is a bulge (group 42) written onto the same LWPOLYLINE, so
;; the round's output is one polyline either way.  Each vertex is given
;; a travel tangent, read off the circle through it and its two
;; neighbours, and each segment is then bent to the angle its two ends
;; agree on.  Points sampled off a real radius therefore reproduce that
;; radius exactly, every arc passes through both of its own points, and
;; a run of points reversed end for end draws the same curve.

;; Unit tangent at pt for the circle centred on ctr, turned to face the
;; way the polyline travels (toward nxt).  nil when there is no circle
;; or pt sits on its centre -- both mean "draw this segment straight".
(defun perp:tan-at (pt ctr nxt / tx ty l)
  (if (null ctr)
    nil
    (progn
      ;; the radius turned 90 degrees is the tangent
      (setq tx (- (cadr ctr) (cadr pt))
            ty (- (car pt)   (car ctr))
            l  (sqrt (+ (* tx tx) (* ty ty))))
      (if (< l 1e-12)
        nil
        (progn
          (setq tx (/ tx l) ty (/ ty l))
          (if (< (+ (* tx (- (car nxt)  (car pt)))
                    (* ty (- (cadr nxt) (cadr pt))))
                 0.0)
            (setq tx (- tx) ty (- ty)))
          (list tx ty))))))

;; the point one more step along from a to b -- b's own heading, for the
;; last vertex, which has nothing in front of it to face
(defun perp:ahead (a b)
  (list (- (* 2.0 (car b))  (car a))
        (- (* 2.0 (cadr b)) (cadr a))
        (caddr b)))

;; Travel tangent at EVERY vertex, in travel order.  An interior vertex
;; takes its direction from the circle through it and its two
;; neighbours; the two end vertices borrow the circle of the triple they
;; sit in.  nil where that circle does not exist -- collinear
;; neighbours, or fewer than three points -- which is how "nothing to
;; curve to" is carried through the rest of the fit.
(defun perp:tangents (pts / n i a p1 p2 p3 nxt ctr out)
  (setq n (length pts) out '() i 0)
  (if (>= n 3)
    (while (< i n)
      ;; a is the first of the three points whose circle points this
      ;; vertex: itself and its neighbours, or the end triple it sits in
      (setq a   (cond ((= i 0) 0) ((= i (1- n)) (- n 3)) (t (1- i)))
            p1  (nth a pts)
            p2  (nth (1+ a) pts)
            p3  (nth (+ a 2) pts)
            ctr (cal:circumcenter p1 p2 p3)
            ;; the last vertex has nothing in front of it to face, so it
            ;; takes its heading from the point before it
            nxt (if (= i (1- n))
                  (perp:ahead (nth (- n 2) pts) (nth (1- n) pts))
                  (nth (1+ i) pts))
            out (cons (perp:tan-at (nth i pts) ctr nxt) out)
            i   (1+ i))))
  (reverse out))

;; signed angle from vector u to vector v, -pi..pi
(defun perp:vang (u v)
  (atan (- (* (car u) (cadr v)) (* (cadr u) (car v)))
        (+ (* (car u) (car v))  (* (cadr u) (cadr v)))))

;; Bulge of the arc from a to b, given the travel tangents at a and at
;; b: tan(alpha/2), where alpha is half the arc's included angle.  Each
;; end asks for an alpha of its own -- the angle from a's tangent to the
;; chord, and from the chord to b's tangent -- and the two agree exactly
;; when the points came off a real circle, so a sampled arc is returned
;; unchanged.  Where they disagree the average is taken, which keeps the
;; fit symmetric: reverse the run of points and every bulge does no more
;; than change sign.  Straight (bulge 0) when neither end has a tangent,
;; which is the middle of a straight run, or when there is no chord.
(defun perp:bulge (ta tb a b / cx cy n alpha lim)
  (setq cx (- (car b)  (car a))
        cy (- (cadr b) (cadr a))
        alpha 0.0
        n     0)
  (cond
    ((< (sqrt (+ (* cx cx) (* cy cy))) 1e-12) 0.0)
    (t
     (if ta (setq alpha (+ alpha (perp:vang ta (list cx cy))) n (1+ n)))
     (if tb (setq alpha (+ alpha (perp:vang (list cx cy) tb)) n (1+ n)))
     (cond
       ((= n 0) 0.0)
       (t
        (setq alpha (/ alpha (float n)))
        ;; a chord folding back on a tangent would blow the bulge up
        ;; toward infinity; cap the included angle at ~342 degrees
        (setq lim 2.98)
        (if (> alpha lim)     (setq alpha lim))
        (if (< alpha (- lim)) (setq alpha (- lim)))
        (/ (sin (/ alpha 2.0)) (cos (/ alpha 2.0))))))))

;; Write the bulges onto the straight LWPOLYLINE en drawn through pts.
;; tangs holds one tangent per vertex.  Segment i (numbered from 1) is
;; arced when picks is nil -- every segment -- or when its number is in
;; picks; the rest are written straight, so one call covers an all-arc
;; round and a mixed one alike.  The entity stays an LWPOLYLINE: only
;; bulges are written, and the vertices are left where they were
;; measured.
(defun perp:arcs (en pts tangs picks / d out g i b)
  (setq d (entget en) out '() i 0)
  (foreach g d
    (cond
      ((= 42 (car g)))                       ; drop existing bulges
      ((= 10 (car g))
       (setq b (if (and (< (1+ i) (length pts))
                        (or (null picks) (member (1+ i) picks)))
                 (perp:bulge (nth i tangs) (nth (1+ i) tangs)
                             (nth i pts) (nth (1+ i) pts))
                 0.0))
       (setq out (cons (cons 42 b) (cons g out))
             i   (1+ i)))
      (t (setq out (cons g out)))))
  (entmod (reverse out)))

;; n points equally spaced by TRUE arc length along an existing polyline
;; entity, in the current UCS (both endpoints included).  This is what a
;; round after an arc round measures along: perp:sample walks the chords
;; between the points, which is the same thing only while the segments
;; are straight.  nil if the entity cannot be measured, so the caller
;; can fall back to the chords.
(defun perp:ent-pts (en n / tot i d p out ok)
  (setq tot (vlax-curve-getDistAtParam en (vlax-curve-getEndParam en))
        out '() i 0 ok T)
  (while (and ok (< i n))
    (setq d (if (> n 1) (* (/ (float i) (float (1- n))) tot) 0.0))
    (if (> d tot) (setq d tot))
    (if (setq p (vlax-curve-getPointAtDist en d))
      (setq out (cons (trans p 0 1) out)
            i   (1+ i))
      (setq ok nil)))
  (if ok (reverse out)))

;; --- reading a typed segment list ------------------------------------

;; T when s is one or more digits and nothing else.
(defun perp:digits-p (s / i n ok)
  (setq n (strlen s) i 1 ok (> n 0))
  (while (and ok (<= i n))
    (if (null (member (substr s i 1)
                      '("0" "1" "2" "3" "4" "5" "6" "7" "8" "9")))
      (setq ok nil))
    (setq i (1+ i)))
  ok)

;; "3" -> (3 3), "3-5" -> (3 5), anything else -> nil.
(defun perp:range (tok / i n p lft rgt)
  (setq n (strlen tok) i 1 p nil)
  (while (and (null p) (<= i n))
    (if (= "-" (substr tok i 1)) (setq p i))
    (setq i (1+ i)))
  (cond
    ((null p)
     (if (perp:digits-p tok) (list (atoi tok) (atoi tok))))
    (t
     (setq lft (substr tok 1 (1- p))
           rgt (substr tok (1+ p)))
     (if (and (perp:digits-p lft) (perp:digits-p rgt))
       (list (atoi lft) (atoi rgt))))))

;; Read a typed segment list -- "1 3-5, 8" -- into a list of segment
;; numbers.  Spaces and commas both separate.  Returns nil for an empty
;; answer, a malformed token or a number outside 1..maxn, so a bad
;; answer re-asks instead of quietly drawing the wrong thing.
(defun perp:parse-segs (s maxn / i n ch tok toks out bad r a b)
  (setq n (strlen s) i 1 tok "" toks '())
  (while (<= i n)
    (setq ch (substr s i 1))
    (if (or (= ch " ") (= ch ","))
      (progn
        (if (/= tok "") (setq toks (cons tok toks)))
        (setq tok ""))
      (setq tok (strcat tok ch)))
    (setq i (1+ i)))
  (if (/= tok "") (setq toks (cons tok toks)))
  (setq out '() bad (null toks))
  (foreach tok toks
    (setq r (perp:range tok))
    (if (null r)
      (setq bad T)
      (progn
        (setq a (car r) b (cadr r))
        (if (or (< a 1) (> b maxn) (> a b))
          (setq bad T)
          (while (<= a b)
            (if (not (member a out)) (setq out (cons a out)))
            (setq a (1+ a)))))))
  (if bad nil out))

;; --- the overall width -----------------------------------------------
;; Widths get re-measured, and the number that comes back is the
;; distance straight across, end to end -- NOT the developed length of
;; the object on the drawing, which on anything bowed is the longer of
;; the two.  Making that width true is one scale about the midpoint of
;; the two ends: exactly half the difference lands at each end, the
;; direction of travel and the offset side are left alone, and the shape
;; between the ends is carried along with it.

;; Ask whether the overall width has changed.  Returns the width to work
;; to, or nil when it has not -- so an unchanged answer skips the resize
;; altogether and the command behaves exactly as it always did.  d is
;; the width the drawing carries now.
(defun perp:ask-width (d / kws ans v w)
  (princ (strcat "\nOverall width, end to end: " (rtos d) "."))
  (setq kws "Grew Shrank New Unchanged")
  (initget kws)
  (setq ans (getkword (strcat "\nHas that width changed? ["
                              (vl-string-translate " " "/" kws)
                              "] <Unchanged>: ")))
  (cond
    ((or (null ans) (= ans "Unchanged")) nil)
    ((= ans "Grew")
     (initget 7)                              ; a real, positive amount
     (+ d (getdist "\nHow much wider? ")))
    ((= ans "Shrank")
     (while (null w)
       (initget 7)
       (setq v (getdist "\nHow much narrower? "))
       (if (< v d)
         (setq w (- d v))
         (princ "\nThat is the whole width or more - nothing would be left.")))
     w)
    (t                                        ; New: the width itself
     (initget 6)                              ; Enter keeps what is drawn
     (setq v (getdist (strcat "\nNew overall width <" (rtos d) ">: ")))
     (if (or (null v) (equal v d 1e-9)) nil v))))

;; Scale en about ctr (a point in the current UCS) by k.  T when the
;; drawing took it, nil when it would not -- a locked, frozen or
;; switched-off layer is the usual reason, and the caller has to say so
;; rather than measure offsets against geometry the drawing does not
;; actually have.
(defun perp:rescale (en ctr k / r)
  (setq r (vl-catch-all-apply
            'vla-ScaleEntity
            (list (vlax-ename->vla-object en)
                  (vlax-3d-point (trans ctr 1 0))
                  k)))
  (not (vl-catch-all-error-p r)))

;; p scaled about ctr by k, in plan; z is carried through untouched
(defun perp:scale-pt (p ctr k)
  (list (+ (car ctr)  (* k (- (car p)  (car ctr))))
        (+ (cadr ctr) (* k (- (cadr p) (cadr ctr))))
        (caddr p)))

;; every point of pts scaled about ctr by k
(defun perp:scale-pts (pts ctr k / out p)
  (setq out '())
  (foreach p pts (setq out (cons (perp:scale-pt p ctr k) out)))
  (reverse out))

;; --- command ---------------------------------------------------------

;; ahead of the command on purpose: the structural tests scan from
;; c:PERPPTS to end-of-file for leaked variables, and a defun name
;; there would read as one
(defun c:PERPPTSVER ()
  (princ (strcat "\nPERPPTS " *perp-version*))
  (princ))

(defun c:PERPPTS (/ *error* perp:kill perp:finish
                    os ce pd plt clay cec celt celw celts cdim undoOpen
                    tmpEnts
                    srcData srcLayer srcColor srcLtype srcLw srcLts
                    dimPairs dimStyle pr
                    sel ent etype verts p1 p2 pStart pFinish click
                    dx dy dlen ux uy cross fuzz nx ny sz
                    arlen hlen tailx taily ca sa bkx bky b1x b1y b2x b2y
                    path pathEnt n lastN basePts newPts guideEnts total
                    len lastLen i base np again ans iter p e seg
                    join lastJoin kws nseg picks reply tangs
                    wOld wNew mid fac)

  ;; erase one temporary entity and forget it
  (defun perp:kill (e)
    (if e
      (progn (if (entget e) (entdel e))
             (setq tmpEnts (vl-remove e tmpEnts)))))

  ;; single cleanup path shared by normal exit, Esc and errors
  (defun perp:finish (/ guard)
    ;; cancel any command left pending by an Esc mid-PLINE/DIMALIGNED
    (setq guard 0)
    (while (and (> (getvar "CMDACTIVE") 0) (< guard 10))
      (command)
      (setq guard (1+ guard)))
    (foreach e tmpEnts (if (and e (entget e)) (entdel e)))
    (setq tmpEnts nil)
    ;; leave the drawing's creation defaults exactly as they were found
    (if cec   (setvar "CECOLOR"   cec))
    (if celt  (setvar "CELTYPE"   celt))
    (if celw  (setvar "CELWEIGHT" celw))
    (if celts (setvar "CELTSCALE" celts))
    (if (and cdim (tblsearch "DIMSTYLE" cdim))
      (command "._-DIMSTYLE" "_Restore" cdim))
    (if clay (setvar "CLAYER"  clay))
    (if pd   (setvar "PDMODE"  pd))
    (if os   (setvar "OSMODE"  os))
    (if plt  (setvar "PLINETYPE" plt))
    (if ce   (setvar "CMDECHO" ce))
    (if undoOpen
      (progn (command "._UNDO" "_End") (setq undoOpen nil))))

  (defun *error* (msg)
    (perp:finish)
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nError: " msg))
      (princ "\nCancelled."))
    (princ))

  ;; --- save state and open one undo group for the whole run -----------
  (setq os    (getvar "OSMODE")
        ce    (getvar "CMDECHO")
        pd    (getvar "PDMODE")
        plt   (getvar "PLINETYPE")
        clay  (getvar "CLAYER")
        cec   (getvar "CECOLOR")
        celt  (getvar "CELTYPE")
        celw  (getvar "CELWEIGHT")
        celts (getvar "CELTSCALE")
        cdim  (getvar "DIMSTYLE")
        tmpEnts '())
  (setvar "CMDECHO" 0)
  ;; PLINE must produce a lightweight polyline, the only kind an arc
  ;; bulge can be written onto
  (setvar "PLINETYPE" 2)
  (command "._UNDO" "_Begin")
  (setq undoOpen T)
  ;; guide points must be visible whatever the drawing's PDMODE is
  (if (member pd '(0 1)) (setvar "PDMODE" 3))

  ;; --- 1. select a line (re-prompts until valid) -----------------------
  (setq ent nil)
  (while (null ent)
    (setq sel (entsel "\nSelect a line or polyline: "))
    (cond
      ((null sel)
       (princ "\nNothing selected - try again, or press Esc to quit."))
      (t
       (setq etype (cdr (assoc 0 (entget (car sel))))
             verts (perp:verts (car sel)))
       (cond
         ((null verts)
          (princ (strcat "\nA " etype " is not a line or polyline.")))
         ((< (length (setq verts (perp:dedupe verts))) 2)
          (princ "\nThat object has no usable length."))
         ((<= (distance (car verts) (last verts)) 1e-9)
          (princ "\nStart and end coincide - a closed shape has no direction."))
         (t (setq ent (car sel)))))))

  (setq p1 (car verts)                       ; first endpoint (UCS)
        p2 (last verts))                     ; last endpoint  (UCS)

  ;; --- 2. has the overall width changed? -------------------------------
  ;; The width asked about is the distance straight across, end to end,
  ;; not the developed length of the object -- a bowed polyline runs
  ;; further than the width it spans, and it is the width that gets
  ;; re-measured.  Making a new one true is a scale about the midpoint of
  ;; the two ends, so exactly half the difference lands at each end.  The
  ;; drawing is resized too: the offsets and their dimensions are
  ;; measured off this object, so leaving it at the old width would put
  ;; every base point somewhere the drawing says nothing is.  It is all
  ;; inside the command's undo group, so one U puts the width back.
  (setq dx   (- (car p2)  (car p1))
        dy   (- (cadr p2) (cadr p1))
        wOld (sqrt (+ (* dx dx) (* dy dy)))
        ;; a plan projection with no width at all has nothing to
        ;; ask about; the direction click below is where that
        ;; gets reported
        wNew (if (> wOld 1e-9) (perp:ask-width wOld)))
  (if wNew
    (progn
      (setq mid (list (/ (+ (car p1)  (car p2))  2.0)
                      (/ (+ (cadr p1) (cadr p2)) 2.0)
                      (caddr p1))
            fac (/ wNew wOld))
      (if (not (perp:rescale ent mid fac))
        (progn
          (princ (strcat "\nThe line could not be resized - it is most"
                         " likely on a locked, frozen or switched-off"
                         " layer.  Free the layer and run PERPPTS again."))
          (perp:finish)
          (exit)))
      (setq verts (perp:scale-pts verts mid fac)
            p1    (car verts)
            p2    (last verts))
      (princ (strcat "\nWidth " (rtos wOld) " -> " (rtos wNew) ": "
                     (rtos (/ (abs (- wNew wOld)) 2.0))
                     (if (> wNew wOld) " added at" " taken off")
                     " each end."))))

  ;; --- properties to give the offset polylines -------------------------
  ;; The new polylines are drawn with the same layer, colour, linetype,
  ;; lineweight and linetype scale as the object they are offset from, so
  ;; they read as the same kind of object in the drawing.  Anything the
  ;; source does not carry explicitly is BYLAYER, which is also the
  ;; correct inherited value.
  (setq srcData  (entget ent)
        srcLayer (cdr (assoc 8 srcData))
        srcColor (perp:color srcData)
        srcLtype (cond ((cdr (assoc 6 srcData))) ("BYLAYER"))
        srcLw    (cond ((cdr (assoc 370 srcData))) (-1))
        srcLts   (cond ((cdr (assoc 48 srcData))) (1.0)))

  ;; --- 3. click to set direction (START/FINISH) and offset side -------
  ;; Snapping is off so the click cannot be pulled onto the line itself,
  ;; which would make "which side" ambiguous.
  (setvar "OSMODE" 0)
  (setq click nil)
  (while (null click)
    (setq click (getpoint "\nClick to pick direction / offset side: "))
    (cond
      ((null click)
       (princ "\nA point is required - click one side of the line."))
      (t
       ;; nearest endpoint to the click = START
       (if (<= (distance click p1) (distance click p2))
         (setq pStart p1 pFinish p2)
         (setq pStart p2 pFinish p1))
       (setq dx   (- (car pFinish)  (car pStart))
             dy   (- (cadr pFinish) (cadr pStart))
             dlen (sqrt (+ (* dx dx) (* dy dy))))
       (cond
         ((equal dlen 0.0 1e-9)
          (princ "\nSelected object has zero length.")
          (perp:finish)
          (exit))
         (t
          (setq ux (/ dx dlen)
                uy (/ dy dlen))
          ;; cross = signed distance from the infinite line;
          ;; >0 => click is on the left.
          (setq cross (- (* ux (- (cadr click) (cadr pStart)))
                         (* uy (- (car click)  (car pStart))))
                fuzz  (max 1e-8 (* dlen 1e-6)))
          (if (< (abs cross) fuzz)
            (progn
              (princ "\nThat point is on the line - click clearly to one side.")
              (setq click nil))))))))

  ;; perpendicular unit vector, chosen toward the clicked side.  This is
  ;; fixed for the whole command: every offset and dimension in every
  ;; round is measured along this direction, i.e. perpendicular to the
  ;; ORIGINAL line -- never to a later polyline.
  (if (>= cross 0.0)
    (setq nx (- uy) ny ux)          ; left normal
    (setq nx uy     ny (- ux)))     ; right normal

  ;; --- prepare the layers ---------------------------------------------
  ;; Guides live on their own layer so a locked current layer cannot stop
  ;; them being erased.  Offset polylines go on the source object's own
  ;; layer; dimensions go on DIMENSIONS.
  (cal:ensure-layer "PERPPTS-TEMP" 1)     ; guides, erased before the command ends
  (cal:ensure-layer "DIMENSIONS"   4)

  ;; --- draw an arrow pointing at the START end ------------------------
  ;; The arrow comes in from outside the line (along the FINISH->START
  ;; extension) with its tip on the START point.  Drawn in red so it is
  ;; visible on any background, and kept until the command finishes so the
  ;; entry order stays clear across repeat rounds.
  (setq sz (caddr pStart))
  (setq arlen (* dlen 0.15))                ; shaft length
  (if (< arlen 1e-6) (setq arlen 1.0))
  (setq hlen (* arlen 0.35))                ; arrowhead barb length
  ;; tail = START minus (shaft along the line direction), tip = START
  (setq tailx (- (car pStart)  (* ux arlen))
        taily (- (cadr pStart) (* uy arlen)))
  ;; barbs: rotate the "back" vector b = (-ux,-uy) by +/-25 degrees
  (setq ca 0.9063 sa 0.4226                 ; cos/sin 25 deg
        bkx (- ux) bky (- uy))
  (setq b1x (+ (car pStart)  (* hlen (- (* bkx ca) (* bky sa))))
        b1y (+ (cadr pStart) (* hlen (+ (* bkx sa) (* bky ca))))
        b2x (+ (car pStart)  (* hlen (+ (* bkx ca) (* bky sa))))
        b2y (+ (cadr pStart) (* hlen (+ (* (- bkx) sa) (* bky ca)))))
  ;; entmade LINE points are WCS, so convert from the current UCS
  (foreach seg (list (list (list tailx taily sz) pStart)
                     (list pStart (list b1x b1y sz))
                     (list pStart (list b2x b2y sz)))
    (entmake (list '(0 . "LINE") '(8 . "PERPPTS-TEMP") '(62 . 1)
                   (cons 10 (trans (car seg)  1 0))
                   (cons 11 (trans (cadr seg) 1 0))))
    (setq tmpEnts (cons (entlast) tmpEnts)))

  ;; --- offset rounds --------------------------------------------------
  ;; the path the points are spaced along.  Round 1 uses the selected
  ;; object, oriented START -> FINISH; each later round uses the polyline
  ;; the previous round built.
  (setq path (if (equal pStart (car verts) 1e-9) verts (reverse verts))
        again "Yes"
        iter  0
        total 0)

  (while (equal again "Yes")
    (setq iter (1+ iter))

    ;; --- how many values / points for this round ---------------------
    ;; Enter reuses the previous round's count.
    (setq n nil)
    (while (null n)
      (initget 6)                            ; no zero, no negative
      (setq n (getint (strcat "\nRound " (itoa iter)
                              " - how many values (points) are required?"
                              (if lastN (strcat " <" (itoa lastN) ">") "")
                              " ")))
      (if (null n) (setq n lastN))           ; Enter = same count as last round
      (cond
        ((null n)
         (princ "\nA number is required."))
        ((< n 2)
         (princ "\nNeed at least 2 points.")
         (setq n nil))
        ((> n 100)
         ;; guard against a mistyped count creating thousands of entities
         (initget "Yes No")
         (setq ans (getkword
                     (strcat "\n" (itoa n) " points means " (itoa n)
                             " dimensions. Continue? [Yes/No] <No>: ")))
         (if (not (equal ans "Yes")) (setq n nil)))))
    (setq lastN n)

    ;; base points, equally spaced along the current path.  The offset
    ;; side (nx,ny) was fixed from the direction click and is reused for
    ;; every round, so all rounds offset to the same side.  A path drawn
    ;; with arcs is measured along the curve itself (pathEnt); a
    ;; straight one is measured along its own points, which is the same
    ;; walk over the chords.
    (setq basePts (cond ((and pathEnt (perp:ent-pts pathEnt n)))
                        ((perp:sample path n))))

    ;; --- length per point + build the new perpendicular points -------
    ;; Enter reuses the last length entered (shown as the prompt
    ;; default), since runs of equal lengths are common; the last value
    ;; carries across rounds.  Back steps back a point (Undo is kept as
    ;; a hidden synonym for old habits).  Zero and negative lengths are
    ;; rejected, so a dimension is never degenerate and the offset can
    ;; never flip to the wrong side.
    (setvar "CLAYER" "PERPPTS-TEMP")
    (setq newPts '() guideEnts '() i 0)
    (while (< i n)
      (setq base (nth i basePts))
      (initget 6 "Back Undo")                ; no zero, no negative
      (setq len (getdist (strcat "\nLength for point " (itoa (1+ i))
                                 " of " (itoa n)
                                 (if lastLen
                                   (strcat " <" (rtos lastLen) ">")
                                   "")
                                 " [Back]: ")))
      (if (null len) (setq len lastLen))     ; Enter = same as last time
      (cond
        ;; step back one point and re-enter it (getdist returned "Back",
        ;; or "Undo" - the old keyword, kept as a synonym)
        ((eq (type len) 'STR)
         (if (> i 0)
           (progn
             (setq i (1- i))
             (perp:kill (car guideEnts))
             (setq guideEnts (cdr guideEnts)
                   newPts    (cdr newPts))
             (princ "\nStepping back one point."))
           (princ "\nAlready at the first point.")))
        ((null len)
         (princ "\nA length is required."))
        (t
         (setq lastLen len
               np      (list (+ (car base)  (* len nx))
                             (+ (cadr base) (* len ny))
                             (caddr base)))
         (setq newPts (cons np newPts))
         ;; temporary POINT node at the new location as a guide
         (command "._POINT" np)
         (setq guideEnts (cons (entlast) guideEnts)
               tmpEnts   (cons (entlast) tmpEnts))
         (setq i (1+ i)))))
    (setq newPts (reverse newPts))

    ;; --- straight lines, arcs, or both -------------------------------
    ;; Straight is what this routine has always drawn and stays the
    ;; opening default; Arcs curves every segment; Mixed asks which
    ;; segment numbers to curve and leaves the rest as lines.  Two
    ;; points make one segment with no neighbouring point to take a
    ;; curvature from, so below three points there is nothing to ask.
    ;; The answer carries across rounds as the offered default.
    (setq nseg  (1- n)
          kws   "Straight Arcs Mixed"
          picks nil)
    (if (null lastJoin) (setq lastJoin "Straight"))
    (if (< n 3)
      (progn
        (princ "\nTwo points make one straight segment - nothing to curve.")
        (setq join "Straight"))
      (setq join nil))
    (while (null join)
      (initget kws)
      (setq join (getkword (strcat "\nRound " (itoa iter)
                                   " - how should the points be joined? ["
                                   (vl-string-translate " " "/" kws)
                                   "] <" lastJoin ">: ")))
      (if (null join) (setq join lastJoin))   ; Enter = same as last round
      ;; Mixed is not an answer on its own - it needs the segment list,
      ;; and Back returns to the question above rather than guessing
      (if (equal join "Mixed")
        (while (and join (null picks))
          (setq reply (getstring T
                        (strcat "\nWhich segments are arcs (1 to "
                                (itoa nseg) ", e.g. 1 3-5)? (B = back): ")))
          (cond
            ((member (strcase reply) '("B" "BACK" "U" "UNDO"))
             (setq join nil))
            ((setq picks (perp:parse-segs reply nseg)))
            (t (princ (strcat "\nSegment numbers run 1 to " (itoa nseg)
                              " - single numbers, ranges like 3-5, or"
                              " both.")))))))
    (setq lastJoin join)

    ;; --- connect the new points with a polyline ----------------------
    ;; drawn with the source object's layer and line properties
    (setvar "CLAYER"    srcLayer)
    (setvar "CECOLOR"   srcColor)
    (setvar "CELTYPE"   srcLtype)
    (setvar "CELWEIGHT" srcLw)
    (setvar "CELTSCALE" srcLts)
    (command "._PLINE")
    (foreach p newPts (command p))
    (command "")
    ;; One tangent per vertex; perp:arcs turns the segments picks names
    ;; into arcs and writes the rest straight, so the same call draws an
    ;; all-arc round and a mixed one.  The polyline keeps its vertices,
    ;; so every arc still runs through the measured points and every
    ;; dimension still lands on the curve.
    (setq tangs (if (equal join "Straight") nil (perp:tangents newPts)))
    (if tangs (perp:arcs (entlast) newPts tangs picks))
    ;; a round that drew arcs is the next round's curve to measure along
    (setq pathEnt (if tangs (entlast)))
    (princ (strcat "\nRound " (itoa iter) ": polyline drawn "
                   (cond ((equal join "Straight") "with straight segments")
                         ((equal join "Arcs")     "with arcs through the points")
                         (t (strcat "with arcs on " (itoa (length picks))
                                    " of " (itoa nseg) " segments")))
                   "."))

    ;; --- erase this round's point guides -----------------------------
    (foreach e guideEnts (perp:kill e))
    (setq guideEnts nil)

    ;; --- remember the dimensions to draw -----------------------------
    ;; np = base + len*(nx,ny), so each dimension runs along the fixed
    ;; normal, i.e. perpendicular to the ORIGINAL line, no matter which
    ;; polyline `base` sits on.  They are drawn once at the end, after
    ;; the dimension style has been chosen.
    (setq i 0)
    (while (< i n)
      (setq dimPairs (cons (list (nth i basePts) (nth i newPts)) dimPairs)
            i        (1+ i)))
    (setq total (+ total n))

    ;; the polyline just built becomes the path for the next round
    (setq path newPts)

    ;; --- repeat? -----------------------------------------------------
    (initget "Yes No")
    (setq again (getkword "\nRepeat on the new polyline? [Yes/No] <No>: "))
    (if (null again) (setq again "No")))

  ;; --- 8. dimension style, then draw every dimension ------------------
  (initget "STandard SIde")
  (setq ans (getkword (strcat "\nDimension style - STANDARD INCHES or "
                              "SIDE STANDARD? [STandard/SIde] <STandard>: ")))
  (setq dimStyle (if (equal ans "SIde") "SIDE STANDARD" "STANDARD INCHES"))
  (if (tblsearch "DIMSTYLE" dimStyle)
    (command "._-DIMSTYLE" "_Restore" dimStyle)
    (princ (strcat "\nDimension style \"" dimStyle
                   "\" is not in this drawing - using the current style \""
                   cdim "\" instead.")))

  (setvar "CLAYER" "DIMENSIONS")
  (foreach pr (reverse dimPairs)
    (command "._DIMALIGNED" (car pr) (cadr pr) (cadr pr)))

  ;; --- restore everything and close the undo group --------------------
  (perp:finish)
  (princ (strcat "\nDone: " (itoa iter) " round(s), "
                 (itoa total) " points, "
                 (itoa iter) " polyline(s) on layer \"" srcLayer "\" and "
                 (itoa total) " dimensions on layer \"DIMENSIONS\"."))
  (princ))

(princ (strcat "\nperp_points.lsp " *perp-version*
               " loaded.  Type PERPPTS to run."))
(princ)
