;;; cperp_points.lsp  --  AutoCAD 2018 (AutoLISP)
;;;
;;; Command: CPERPPTS   ("C" for curved)
;;;
;;; The curved-geometry companion to PERPPTS (perp_points.lsp).  Same
;;; workflow and same pipeline, but the offsets are taken perpendicular
;;; to the TANGENT of the curve rather than to a straight line, so arcs,
;;; bulged polylines and splines can be offset with a different length
;;; at every point.
;;;
;;; Works on anything AutoCAD treats as a curve: LWPOLYLINE (including
;;; arc/bulge segments), POLYLINE, LINE, ARC, ELLIPSE and SPLINE.
;;;
;;; The offset points are joined into a single LWPOLYLINE whose
;;; segments are ARCS (bulges), each arc matched to the curve's tangent
;;; direction at its start point.  The result is a smooth POLYLINE
;;; curve passing exactly through every offset point -- a real
;;; lightweight polyline, never a spline and never a curve-fit heavy
;;; polyline.
;;;
;;; Points are spaced by true arc length along the curve, so spacing
;;; stays even through curved segments instead of bunching up.
;;;
;;; Workflow
;;;   1. Select a curve (open, i.e. not a closed loop).
;;;   2. Say whether the overall width has changed: Grew, Shrank, New
;;;      or Unchanged.  The width meant is the distance straight across,
;;;      end to end, not the length of the curve; half of any difference
;;;      is added to (or taken off) each end, and the curve in the
;;;      drawing is resized to match.
;;;   3. Click a point to set the direction:
;;;        - the curve end nearest the click becomes START, the far end
;;;          FINISH, fixing the order the lengths are entered in;
;;;        - the side of the curve the click lands on is the side the
;;;          new points are offset toward.
;;;   4. Enter how many values (points) are required  (>= 2).
;;;   5. Enter a length for each point, in order START -> FINISH.
;;;      Press Enter to reuse the previous length when it repeats, or
;;;      type B (Back) to step back and re-enter the previous point
;;;      (U, the old keyword, is still accepted).
;;;   6. Choose whether to repeat on the new polyline.  If so, enter a
;;;      new point count and repeat from step 5 with the new polyline as
;;;      the path.
;;;   7. Pick the dimension style, STANDARD INCHES or SIDE STANDARD.
;;;      Every dimension is then drawn at once, on the DIMENSIONS layer.
;;;
;;; The overall width
;;;   Walls get re-measured, and the number that comes back is the
;;;   distance straight across, end to end.  That is what step 2 asks
;;;   for -- never the developed length of the CURVE, which on anything
;;;   bowed runs further than the width it spans.  Grew and Shrank take
;;;   the difference, New takes the width itself, and Unchanged (the
;;;   default, and Enter) leaves everything exactly as it was.
;;;
;;;   A new width is made true by scaling the selected curve about the
;;;   midpoint of its two ends, so exactly half the difference lands at
;;;   each end and the curve keeps its shape: an arc stays that arc,
;;;   scaled.  The curve in the drawing is resized too, not just the
;;;   numbers behind it -- the offsets and their dimensions are measured
;;;   off it, so leaving it at the old width would put every base point
;;;   somewhere the drawing says nothing is.  The base points and
;;;   dimensions then follow the resized curve, since they are spaced
;;;   along it after the resize.  The whole thing sits inside the
;;;   command's undo group, so one U puts the width back.
;;;
;;; How the offset direction is found
;;;   Every round works from the NEWEST curve.  Round 1 offsets from the
;;;   selected curve; each later round offsets from the arc polyline
;;;   the previous round built.  Each base point sits on that
;;;   newest curve, and its offset runs along the normal of the curve's
;;;   tangent underneath it -- so both the offset and its dimension read
;;;   perpendicular to the line the point actually sits on, and each
;;;   round follows the shape its predecessor took.
;;;
;;;   Which side is used is fixed once, from the direction click,
;;;   relative to the direction of travel (START -> FINISH), so every
;;;   point in every round offsets to the same side however the curves
;;;   bend.
;;;
;;; Properties
;;;   * The offset polylines take the layer, colour, linetype, lineweight
;;;     and linetype scale of the curve they were offset from.
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
;;;     on the curve itself (where "which side" would be ambiguous).
;;;   * All geometry is handled in the current UCS, so the command works
;;;     in a rotated or shifted UCS.
;;;
;;; Note: on a tight concave bend, normals converge and large offsets
;;; can make the new curve cross itself -- inherent to offsetting along
;;; normals, not a fault of the routine.  The arc segments pass exactly
;;; through every offset point, so each dimension's endpoint lies on
;;; the new curve.
;;;
;;; License: GPL-3.0-or-later
;;; ---------------------------------------------------------------------

(vl-load-com)

;; Version banner: tools/release_lisp.py reads it to stamp the dated
;; REV twin in releases/ (vN.M -> _MMDDYY_REVNM).
(setq *cperp-version* "v0.10")

;; --- generic helpers -------------------------------------------------

;; colour of an entity as a CECOLOR string ("BYLAYER", "3", "12,34,56")
(defun cperp:color (d / c tc)
  (cond
    ((setq tc (cdr (assoc 420 d)))
     (strcat (itoa (logand (lsh tc -16) 255)) ","
             (itoa (logand (lsh tc -8) 255)) ","
             (itoa (logand tc 255))))
    ((setq c (cdr (assoc 62 d)))
     (cond ((= c 0) "BYBLOCK")
           ((= c 256) "BYLAYER")
           (t (itoa (abs c)))))
    (t "BYLAYER")))

;; make sure a layer exists and is usable (thawed, unlocked, on).
;; Repairs through entmod - no command echo, and safe to call from the
;; error handler - and SAYS so when it had to: a run that quietly
;; un-freezes a layer leaves the user wondering why their drawing
;; changed.  (The canonical body of STANDARDS section 5; the grouped
;; build swaps this whole helper for cal:ensure-layer, which has
;; announced all along - this is the standalone tier catching up.)
(defun cperp:layer (name color / rec ed flags col fixed)
  (if (not (tblsearch "LAYER" name))
    (entmake (list '(0 . "LAYER")
                   '(100 . "AcDbSymbolTableRecord")
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

;; --- curve helpers ---------------------------------------------------
;; vlax-curve-* works on any curve entity and always speaks WCS, so the
;; results are converted into the current UCS as they come back.

;; is this entity something AutoCAD can measure along?
(defun cperp:curve-p (e / r)
  (setq r (vl-catch-all-apply 'vlax-curve-getEndParam (list e)))
  (and r (not (vl-catch-all-error-p r))))

;; total length of the curve
(defun cperp:curvelen (crv)
  (vlax-curve-getDistAtParam crv (vlax-curve-getEndParam crv)))

;; point at arc-length distance d along the curve, in the current UCS
(defun cperp:pt-at-dist (crv d tot / p)
  (setq d (cond ((< d 0.0) 0.0) ((> d tot) tot) (t d)))
  (if (setq p (vlax-curve-getPointAtDist crv d))
    (trans p 0 1)))

;; n points equally spaced by arc length along the curve, START first.
;; rev traverses the curve from its far end.
(defun cperp:curve-pts (crv n rev / tot i d out)
  (setq tot (cperp:curvelen crv) out '() i 0)
  (while (< i n)
    (setq d (* (/ (float i) (float (1- n))) tot))
    (if rev (setq d (- tot d)))
    (setq out (cons (cperp:pt-at-dist crv d tot) out)
          i   (1+ i)))
  (reverse out))

;; Unit tangent of the curve (current UCS) at the point of the curve
;; closest to pt, as a 2D (x y) vector.  rev flips it so the tangent
;; follows the direction of travel when the curve is being traversed
;; from its far end.  Returns nil at a cusp.
(defun cperp:tangent (crv pt rev / w p prm d dx dy dl)
  (setq w   (trans pt 1 0)
        p   (vlax-curve-getClosestPointTo crv w))
  (if (null p)
    nil
    (progn
      (setq prm (vlax-curve-getParamAtPoint crv p))
      ;; floating point can put the projected point a hair off the curve
      (if (null prm)
        (setq prm (vlax-curve-getParamAtDist
                    crv (vlax-curve-getDistAtPoint crv p))))
      (if (null prm)
        nil
        (progn
          ;; a derivative is a direction, so transform it as a displacement
          (setq d  (trans (vlax-curve-getFirstDeriv crv prm) 0 1 T)
                dx (car d)
                dy (cadr d)
                dl (sqrt (+ (* dx dx) (* dy dy))))
          (if (< dl 1e-12)
            nil
            (progn
              (if rev (setq dx (- dx) dy (- dy)))
              (list (/ dx dl) (/ dy dl)))))))))

;; Bulge of the arc from a to b whose tangent at a is tg: tan(alpha/2)
;; where alpha is the signed angle from the tangent to the chord (the
;; arc's included angle is 2*alpha).  Sampling a circle this way
;; reproduces the circle exactly.  Falls back to a straight segment
;; (bulge 0) when there is no tangent or no chord.
(defun cperp:bulge (tg a b / cx cy dot crs alpha lim)
  (setq cx (- (car b) (car a))
        cy (- (cadr b) (cadr a)))
  (if (or (null tg)
          (< (sqrt (+ (* cx cx) (* cy cy))) 1e-12))
    0.0
    (progn
      (setq dot   (+ (* (car tg) cx) (* (cadr tg) cy))
            crs   (- (* (car tg) cy) (* (cadr tg) cx))
            alpha (atan crs dot))
      ;; a chord folding back on the tangent would blow the bulge up
      ;; toward infinity; cap the included angle at ~342 degrees
      (setq lim 2.98)
      (if (> alpha lim)     (setq alpha lim))
      (if (< alpha (- lim)) (setq alpha (- lim)))
      (/ (sin (/ alpha 2.0)) (cos (/ alpha 2.0))))))

;; Turn the straight LWPOLYLINE en (drawn through pts, whose travel
;; tangents are tangs) into an arc polyline: every segment becomes an
;; arc matched to the tangent at its start point.  The entity stays an
;; LWPOLYLINE -- only bulge values are written.
(defun cperp:arcs (en pts tangs / d out g i b)
  (setq d (entget en) out '() i 0)
  (foreach g d
    (cond
      ((= 42 (car g)))                       ; drop existing bulges
      ((= 10 (car g))
       (setq b (if (< (1+ i) (length pts))
                 (cperp:bulge (nth i tangs) (nth i pts) (nth (1+ i) pts))
                 0.0))
       (setq out (cons (cons 42 b) (cons g out))
             i   (1+ i)))
      (t (setq out (cons g out)))))
  (entmod (reverse out)))

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
(defun cperp:ask-width (d / kws ans v w)
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
(defun cperp:rescale (en ctr k / r)
  (setq r (vl-catch-all-apply
            'vla-ScaleEntity
            (list (vlax-ename->vla-object en)
                  (vlax-3d-point (trans ctr 1 0))
                  k)))
  (not (vl-catch-all-error-p r)))

;; --- command ---------------------------------------------------------

;; ahead of the command on purpose: the structural tests scan from
;; c:CPERPPTS to end-of-file for leaked variables, and a defun name
;; there would read as one
(defun c:CPERPPTSVER ()
  (princ (strcat "\nCPERPPTS " *cperp-version*))
  (princ))

(defun c:CPERPPTS (/ *error* cperp:kill cperp:finish
                     os ce pd clay cec celt celw celts cdim undoOpen tmpEnts
                     srcData srcLayer srcColor srcLtype srcLw srcLts
                     dimPairs dimStyle pr
                     sel crv etype sp ep click rev side tot
                     tng prj cross fuzz nrm sz
                     arlen hlen p2 tx ty tailx taily ca sa bkx bky
                     b1x b1y b2x b2y
                     curCrv curRev n lastN basePts newPts usedBases idxs
                     tangs tg guideEnts total len lastLen i base np again
                     ans iter plt p e seg
                     wOld wNew mid fac)

  ;; erase one temporary entity and forget it
  (defun cperp:kill (e)
    (if e
      (progn (if (entget e) (entdel e))
             (setq tmpEnts (vl-remove e tmpEnts)))))

  ;; single cleanup path shared by normal exit, Esc and errors
  (defun cperp:finish (/ guard)
    (setq guard 0)
    (while (and (> (getvar "CMDACTIVE") 0) (< guard 10))
      (command)
      (setq guard (1+ guard)))
    (foreach e tmpEnts (if (and e (entget e)) (entdel e)))
    (setq tmpEnts nil)
    (if cec   (setvar "CECOLOR"   cec))
    (if celt  (setvar "CELTYPE"   celt))
    (if celw  (setvar "CELWEIGHT" celw))
    (if celts (setvar "CELTSCALE" celts))
    (if (and cdim (tblsearch "DIMSTYLE" cdim))
      (vl-catch-all-apply 'command-s (list "_.-DIMSTYLE" "_Restore" cdim)))
    (if clay (setvar "CLAYER"  clay))
    (if pd   (setvar "PDMODE"  pd))
    (if os   (setvar "OSMODE"  os))
    (if plt  (setvar "PLINETYPE" plt))
    (if ce   (setvar "CMDECHO" ce))
    (if undoOpen
      (progn (vl-catch-all-apply 'command-s (list "_.UNDO" "_End"))
             (setq undoOpen nil)))
    ;; and the error mode pushed below comes off the stack on EVERY way
    ;; out, since both exits come through here.  Popping only from the
    ;; handler left a clean run's mode stacked for the whole session,
    ;; and a stacked mode refuses command-s inside every later handler
    ;; (AutoLISP reference, *push-error-using-command*).
    (if *pop-error-mode* (*pop-error-mode*)))

  (defun *error* (msg)
    (cperp:finish)
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nError: " msg))
      (princ "\nCancelled."))
    (princ))
  ;; AutoCAD 2012+ requires this so *error* may call (command) - the
  ;; CMDACTIVE drain in cperp:finish; harmless no-op guard on older
  ;; releases where it doesn't exist
  (if *push-error-using-command* (*push-error-using-command*))

  ;; --- save state and open one undo group for the whole run -----------
  (setq os    (getvar "OSMODE")
        ce    (getvar "CMDECHO")
        pd    (getvar "PDMODE")
        clay  (getvar "CLAYER")
        cec   (getvar "CECOLOR")
        celt  (getvar "CELTYPE")
        celw  (getvar "CELWEIGHT")
        celts (getvar "CELTSCALE")
        cdim  (getvar "DIMSTYLE")
        plt   (getvar "PLINETYPE")
        tmpEnts '())
  (setvar "CMDECHO" 0)
  ;; PLINE must produce a lightweight polyline so the arc bulges can be
  ;; written into it and the result stays a plain LWPOLYLINE
  (setvar "PLINETYPE" 2)
  ;; only when undo is recording - _Begin in a drawing with UNDO
  ;; off (bit 1 of UNDOCTL clear) errors out of the command
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn
      (command "_.UNDO" "_Begin")
      (setq undoOpen T)))
  (if (member pd '(0 1)) (setvar "PDMODE" 3))

  ;; --- 1. select a curve (re-prompts until valid) ----------------------
  (setq crv nil)
  (while (null crv)
    (setq sel (entsel "\nSelect a curve (polyline, arc, spline...): "))
    (cond
      ((null sel)
       (princ "\nNothing selected - try again, or press Esc to quit."))
      (t
       (setq etype (cdr (assoc 0 (entget (car sel)))))
       (cond
         ((not (cperp:curve-p (car sel)))
          (princ (strcat "\nA " etype " is not a curve.")))
         ((< (cperp:curvelen (car sel)) 1e-9)
          (princ "\nThat curve has no length."))
         ((equal (vlax-curve-getStartPoint (car sel))
                 (vlax-curve-getEndPoint (car sel)) 1e-9)
          (princ (strcat "\nThat curve is closed, so it has no start or"
                         " end - use an open curve.")))
         (t (setq crv (car sel)))))))

  (setq tot (cperp:curvelen crv)
        sp  (trans (vlax-curve-getStartPoint crv) 0 1)
        ep  (trans (vlax-curve-getEndPoint crv) 0 1))

  ;; --- 2. has the overall width changed? -------------------------------
  ;; The width asked about is the distance straight across, end to end --
  ;; NOT the length of the curve, which on anything bowed runs a good
  ;; deal further than the width it spans, and it is the width that gets
  ;; re-measured.  Making a new one true is a scale about the midpoint of
  ;; the two ends, so exactly half the difference lands at each end and
  ;; the curve keeps its shape: an arc stays that arc, scaled.  The
  ;; drawing is resized too -- the offsets and their dimensions are
  ;; measured off this curve, so leaving it at the old width would put
  ;; every base point somewhere the drawing says nothing is.  It is all
  ;; inside the command's undo group, so one U puts the width back.
  (setq tx   (- (car ep)  (car sp))
        ty   (- (cadr ep) (cadr sp))
        wOld (sqrt (+ (* tx tx) (* ty ty)))
        ;; a plan projection with no width at all has nothing to
        ;; ask about; the direction click below is where that
        ;; gets reported
        wNew (if (> wOld 1e-9) (cperp:ask-width wOld)))
  (if wNew
    (progn
      (setq mid (list (/ (+ (car sp)  (car ep))  2.0)
                      (/ (+ (cadr sp) (cadr ep)) 2.0)
                      (caddr sp))
            fac (/ wNew wOld))
      (if (not (cperp:rescale crv mid fac))
        (progn
          (princ (strcat "\nThe curve could not be resized - it is most"
                         " likely on a locked, frozen or switched-off"
                         " layer.  Free the layer and run CPERPPTS again."))
          (cperp:finish)
          (exit)))
      ;; re-read: the curve itself is what every round measures along
      (setq tot (cperp:curvelen crv)
            sp  (trans (vlax-curve-getStartPoint crv) 0 1)
            ep  (trans (vlax-curve-getEndPoint crv) 0 1))
      (princ (strcat "\nWidth " (rtos wOld) " -> " (rtos wNew) ": "
                     (rtos (/ (abs (- wNew wOld)) 2.0))
                     (if (> wNew wOld) " added at" " taken off")
                     " each end."))))

  ;; --- properties to give the offset polylines -------------------------
  (setq srcData  (entget crv)
        srcLayer (cdr (assoc 8 srcData))
        srcColor (cperp:color srcData)
        srcLtype (cond ((cdr (assoc 6 srcData))) ("BYLAYER"))
        srcLw    (cond ((cdr (assoc 370 srcData))) (-1))
        srcLts   (cond ((cdr (assoc 48 srcData))) (1.0)))

  ;; --- 3. click to set direction (START/FINISH) and offset side -------
  ;; The side is measured against the direction of travel (START ->
  ;; FINISH), so later rounds -- whose curves are built in travel order
  ;; -- inherit the same side directly.
  (setvar "OSMODE" 0)
  (setq click nil)
  (while (null click)
    (setq click (getpoint "\nClick to pick direction / offset side: "))
    (cond
      ((null click)
       (princ "\nA point is required - click one side of the curve."))
      (t
       ;; nearest end of the curve to the click = START
       (setq rev (> (distance click sp) (distance click ep)))
       (cond
         ((null (setq tng (cperp:tangent crv click rev)))
          (princ "\nCannot read the curve direction there - click elsewhere.")
          (setq click nil))
         (t
          ;; signed offset of the click from the tangent line at the
          ;; projection of the click onto the curve
          (setq prj (trans (vlax-curve-getClosestPointTo
                             crv (trans click 1 0))
                           0 1))
          (setq cross (- (* (car tng)  (- (cadr click) (cadr prj)))
                         (* (cadr tng) (- (car click)  (car prj))))
                fuzz  (max 1e-8 (* tot 1e-6)))
          (if (< (abs cross) fuzz)
            (progn
              (princ "\nThat point is on the curve - click clearly to one side.")
              (setq click nil))))))))

  (setq side (if (>= cross 0.0) 1.0 -1.0))

  ;; --- prepare the layers ---------------------------------------------
  (cperp:layer "PERPPTS-TEMP" 1)
  (cperp:layer "DIMENSIONS"   4)

  ;; --- draw an arrow pointing at the START end ------------------------
  ;; The shaft runs back from START along the curve's tangent there, so
  ;; the arrow sits outside the curve pointing at the end the lengths
  ;; are entered from.
  (setq p  (if rev ep sp)
        sz (caddr p))
  ;; a point a little way along the traversal gives the start tangent
  (setq p2 (cperp:pt-at-dist crv
                             (if rev (- tot (* tot 0.001)) (* tot 0.001))
                             tot))
  (setq tx (- (car p2)  (car p))
        ty (- (cadr p2) (cadr p)))
  (if (< (distance p p2) 1e-9)
    (setq tx 1.0 ty 0.0)
    (setq tx (/ tx (distance p p2))
          ty (/ ty (distance p p2))))
  (setq arlen (* tot 0.15))
  (if (< arlen 1e-6) (setq arlen 1.0))
  (setq hlen  (* arlen 0.35)
        tailx (- (car p)  (* tx arlen))
        taily (- (cadr p) (* ty arlen)))
  (setq ca 0.9063 sa 0.4226                 ; cos/sin 25 deg
        bkx (- tx) bky (- ty))
  (setq b1x (+ (car p)  (* hlen (- (* bkx ca) (* bky sa))))
        b1y (+ (cadr p) (* hlen (+ (* bkx sa) (* bky ca))))
        b2x (+ (car p)  (* hlen (+ (* bkx ca) (* bky sa))))
        b2y (+ (cadr p) (* hlen (+ (* (- bkx) sa) (* bky ca)))))
  (foreach seg (list (list (list tailx taily sz) p)
                     (list p (list b1x b1y sz))
                     (list p (list b2x b2y sz)))
    (entmake (list '(0 . "LINE") '(8 . "PERPPTS-TEMP") '(62 . 1)
                   (cons 10 (trans (car seg)  1 0))
                   (cons 11 (trans (cadr seg) 1 0))))
    (setq tmpEnts (cons (entlast) tmpEnts)))

  ;; --- offset rounds --------------------------------------------------
  ;; Every round samples and offsets from the NEWEST curve: the selected
  ;; curve in round 1 (traversed from the clicked end), then the
  ;; arc polyline each round builds.  Later curves are built in travel
  ;; order, so their traversal is never reversed.
  (setq curCrv crv
        curRev rev
        again  "Yes"
        iter   0
        total  0)

  (while (equal again "Yes")
    (setq iter (1+ iter))

    ;; --- how many values / points for this round ---------------------
    (setq n nil)
    (while (null n)
      (initget 6)
      (setq n (getint (strcat "\nRound " (itoa iter)
                              " - how many values (points) are required?"
                              (if lastN (strcat " <" (itoa lastN) ">") "")
                              " ")))
      (if (null n) (setq n lastN))
      (cond
        ((null n)
         (princ "\nA number is required."))
        ((< n 2)
         (princ "\nNeed at least 2 points.")
         (setq n nil))
        ((> n 100)
         (initget "Yes No")
         (setq ans (getkword
                     (strcat "\n" (itoa n) " points means " (itoa n)
                             " dimensions. Continue? [Yes/No] <No>: ")))
         (if (not (equal ans "Yes")) (setq n nil)))))
    (setq lastN n)

    ;; base points, equally spaced by true arc length along the newest
    ;; curve, START first
    (setq basePts (cperp:curve-pts curCrv n curRev))

    ;; --- length per point + build the new perpendicular points -------
    ;; usedBases collects the base of each created point so bases and
    ;; new points stay paired even when a point is skipped; tangs holds
    ;; the travel tangent under each created point (it becomes the arc
    ;; direction of the new polyline there); idxs records each created
    ;; point's position so Back returns to the right prompt even across
    ;; skipped points.
    (setvar "CLAYER" "PERPPTS-TEMP")
    (setq newPts '() usedBases '() tangs '() idxs '() guideEnts '() i 0)
    (while (< i n)
      (setq base (nth i basePts)
            tg   (cperp:tangent curCrv base curRev)
            nrm  (if tg (list (* side (- (cadr tg))) (* side (car tg)))))
      (cond
        ;; no readable tangent under this point - skip it rather than
        ;; place the offset in an arbitrary direction
        ((null nrm)
         (princ (strcat "\nSkipping point " (itoa (1+ i))
                        ": the curve direction cannot be read there."))
         (setq i (1+ i)))
        (t
         (initget 6 "Back Undo")     ; Undo kept as a hidden synonym
         (setq len (getdist (strcat "\nLength for point " (itoa (1+ i))
                                    " of " (itoa n)
                                    (if lastLen
                                      (strcat " <" (rtos lastLen) ">")
                                      "")
                                    " [Back]: ")))
         (if (null len) (setq len lastLen))
         (cond
           ((eq (type len) 'STR)
            (if newPts
              (progn
                (setq i (car idxs))          ; back to that point's prompt
                (cperp:kill (car guideEnts))
                (setq guideEnts (cdr guideEnts)
                      newPts    (cdr newPts)
                      usedBases (cdr usedBases)
                      tangs     (cdr tangs)
                      idxs      (cdr idxs))
                (princ "\nStepping back one point."))
              (princ "\nAlready at the first point.")))
           ((null len)
            (princ "\nA length is required."))
           (t
            (setq lastLen len
                  np      (list (+ (car base)  (* len (car nrm)))
                                (+ (cadr base) (* len (cadr nrm)))
                                (caddr base)))
            (setq newPts    (cons np newPts)
                  usedBases (cons base usedBases)
                  tangs     (cons tg tangs)
                  idxs      (cons i idxs))
            (command "._POINT" np)
            (setq guideEnts (cons (entlast) guideEnts)
                  tmpEnts   (cons (entlast) tmpEnts))
            (setq i (1+ i)))))))
    (setq newPts    (reverse newPts)
          usedBases (reverse usedBases)
          tangs     (reverse tangs))

    ;; --- connect the new points with a polyline ----------------------
    ;; drawn with the source curve's layer and line properties.  If
    ;; skipped points left fewer than 2, there is nothing to join and
    ;; nothing for the next round to follow.
    (if (< (length newPts) 2)
      (progn
        (princ "\nToo few points were placed to build a polyline.")
        (cperp:finish)
        (exit)))
    (setvar "CLAYER"    srcLayer)
    (setvar "CECOLOR"   srcColor)
    (setvar "CELTYPE"   srcLtype)
    (setvar "CELWEIGHT" srcLw)
    (setvar "CELTSCALE" srcLts)
    (command "._PLINE")
    (foreach p newPts (command p))
    (command "")
    ;; Curve it: every straight segment becomes an arc whose direction
    ;; at its start point matches the source curve's tangent there (an
    ;; offset curve runs parallel to its source, so the tangent carries
    ;; over).  The entity stays a plain LWPOLYLINE -- smooth, passing
    ;; exactly through every offset point, and never a spline.
    (cperp:arcs (entlast) newPts tangs)

    ;; the curve just built becomes the source for the next round; it
    ;; was drawn in travel order, so it is never traversed reversed
    (setq curCrv (entlast)
          curRev nil)

    ;; --- erase this round's point guides -----------------------------
    (foreach e guideEnts (cperp:kill e))
    (setq guideEnts nil)

    ;; --- remember the dimensions to draw -----------------------------
    ;; each pair runs along the normal of the curve the base point sits
    ;; on, so the dimension reads perpendicular to that curve
    (setq i 0)
    (while (< i (length newPts))
      (setq dimPairs (cons (list (nth i usedBases) (nth i newPts)) dimPairs)
            i        (1+ i)))
    (setq total (+ total (length newPts)))

    ;; --- repeat? -----------------------------------------------------
    (initget "Yes No")
    (setq again (getkword "\nRepeat on the new polyline? [Yes/No] <No>: "))
    (if (null again) (setq again "No")))

  ;; --- 6. dimension style, then draw every dimension ------------------
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
  (cperp:finish)
  (princ (strcat "\nDone: " (itoa iter) " round(s), "
                 (itoa total) " points, "
                 (itoa iter) " polyline(s) on layer \"" srcLayer "\" and "
                 (itoa total) " dimensions on layer \"DIMENSIONS\"."))
  (princ))

(princ (strcat "\ncperp_points.lsp " *cperp-version*
               " loaded.  Type CPERPPTS to run."))
(princ)
