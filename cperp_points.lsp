;;; cperp_points.lsp  --  AutoCAD 2018 (AutoLISP)
;;;
;;; Command: CPERPPTS   ("C" for curved)
;;;
;;; The curved-geometry companion to PERPPTS (perp_points.lsp).  Same
;;; workflow and same pipeline, but the offsets are taken perpendicular
;;; to the TANGENT of the selected curve rather than to a straight line,
;;; so arcs, bulged polylines and splines can be offset with a different
;;; length at every point.
;;;
;;; Works on anything AutoCAD treats as a curve: LWPOLYLINE (including
;;; arc/bulge segments), POLYLINE, LINE, ARC, ELLIPSE and SPLINE.
;;;
;;; Points are spaced by true arc length along the curve, so spacing
;;; stays even through curved segments instead of bunching up.
;;;
;;; Workflow
;;;   1. Select a curve (open, i.e. not a closed loop).
;;;   2. Click a point to set the direction:
;;;        - the curve end nearest the click becomes START, the far end
;;;          FINISH, fixing the order the lengths are entered in;
;;;        - the side of the curve the click lands on is the side the
;;;          new points are offset toward.
;;;   3. Enter how many values (points) are required  (>= 2).
;;;   4. Enter a length for each point, in order START -> FINISH.
;;;      Press Enter to reuse the previous length when it repeats, or
;;;      type U to step back and re-enter the previous point.
;;;   5. Choose whether to repeat on the new polyline.  If so, enter a
;;;      new point count and repeat from step 4 with the new polyline as
;;;      the path.
;;;   6. Pick the dimension style, STANDARD INCHES or SIDE STANDARD.
;;;      Every dimension is then drawn at once, on the DIMENSIONS layer.
;;;
;;; How the offset direction is found
;;;   Each base point is projected onto the ORIGINAL curve, and the
;;;   offset runs along the normal of the curve's tangent at that
;;;   projection.  In round 1 the base points sit on the curve, so this
;;;   is simply the tangent underneath each point.  In later rounds the
;;;   base points sit on the polyline built by the previous round, and
;;;   projecting them back means every dimension still reads
;;;   perpendicular to the ORIGINAL curve -- never to the polyline the
;;;   points currently lie on.  Offsets therefore accumulate along the
;;;   same normal ray, exactly as they do along the fixed perpendicular
;;;   in PERPPTS.
;;;
;;;   Which side of the curve is used is fixed once, from the direction
;;;   click, relative to the curve's own direction, so every point in
;;;   every round offsets to the same side however the curve bends.
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
;;; Note: the offset points are joined with straight segments, so a
;;; curved result is only as smooth as the number of points asked for.
;;; On a tight concave bend, normals converge and large offsets can make
;;; the new polyline cross itself -- inherent to offsetting along
;;; normals, not a fault of the routine.
;;;
;;; License: GPL-3.0-or-later
;;; ---------------------------------------------------------------------

(vl-load-com)

;; --- generic helpers -------------------------------------------------

;; linear interpolation between two 3D points at parameter tt (0..1)
(defun cperp:lerp (a b tt)
  (list (+ (car a)   (* tt (- (car b)   (car a))))
        (+ (cadr a)  (* tt (- (cadr b)  (cadr a))))
        (+ (caddr a) (* tt (- (caddr b) (caddr a))))))

;; total length of a polyline given as a list of points
(defun cperp:pathlen (pts / total i)
  (setq total 0.0 i 0)
  (while (< (1+ i) (length pts))
    (setq total (+ total (distance (nth i pts) (nth (1+ i) pts)))
          i     (1+ i)))
  total)

;; point at arc-length distance d along the polyline pts
(defun cperp:pt-at (pts d / i a b segd res)
  (cond
    ((<= d 0.0) (car pts))
    (t
     (setq i 0 res nil)
     (while (and (null res) (< (1+ i) (length pts)))
       (setq a    (nth i pts)
             b    (nth (1+ i) pts)
             segd (distance a b))
       (if (<= d segd)
         (setq res (cperp:lerp a b (if (> segd 1e-12) (/ d segd) 0.0)))
         (setq d (- d segd) i (1+ i))))
     (if res res (last pts)))))

;; n points equally spaced by arc length along the polyline pts
(defun cperp:sample (pts n / total i out)
  (setq total (cperp:pathlen pts) out '() i 0)
  (while (< i n)
    (setq out (cons (cperp:pt-at pts
                                 (if (> n 1)
                                   (* (/ (float i) (float (1- n))) total)
                                   0.0))
                    out)
          i   (1+ i)))
  (reverse out))

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

;; make sure a layer exists and is usable (thawed, unlocked, on)
(defun cperp:layer (nm col / en d)
  (if (setq en (tblobjname "LAYER" nm))
    (progn
      (setq d (entget en))
      (setq d (subst (cons 70 (logand (cdr (assoc 70 d)) (~ 5)))
                     (assoc 70 d) d))
      (if (< (cdr (assoc 62 d)) 0)
        (setq d (subst (cons 62 (abs (cdr (assoc 62 d)))) (assoc 62 d) d)))
      (entmod d))
    (entmake (list '(0 . "LAYER")
                   '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord")
                   (cons 2 nm) '(70 . 0) (cons 62 col)
                   '(6 . "Continuous"))))
  nm)

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
;; closest to pt, as a 2D (x y) vector.  Returns nil at a cusp.
(defun cperp:tangent (crv pt / w p prm d dx dy dl)
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
          (if (< dl 1e-12) nil (list (/ dx dl) (/ dy dl))))))))

;; Unit normal to the curve at the projection of pt, on the chosen side.
;; side is 1.0 (left of the curve's own direction) or -1.0 (right).
(defun cperp:normal (crv pt side / t2)
  (if (setq t2 (cperp:tangent crv pt))
    (list (* side (- (cadr t2))) (* side (car t2)))))

;; --- command ---------------------------------------------------------

(defun c:CPERPPTS (/ *error* cperp:kill cperp:finish
                     os ce pd clay cec celt celw celts cdim undoOpen tmpEnts
                     srcData srcLayer srcColor srcLtype srcLw srcLts
                     dimPairs dimStyle pr
                     sel crv etype sp ep click rev side tot
                     tng cross fuzz nrm sz
                     arlen hlen p2 tx ty tailx taily ca sa bkx bky
                     b1x b1y b2x b2y
                     path n lastN basePts newPts usedBases idxs guideEnts
                     total len lastLen i base np again ans iter p e seg)

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
      (command "._-DIMSTYLE" "_Restore" cdim))
    (if clay (setvar "CLAYER"  clay))
    (if pd   (setvar "PDMODE"  pd))
    (if os   (setvar "OSMODE"  os))
    (if ce   (setvar "CMDECHO" ce))
    (if undoOpen
      (progn (command "._UNDO" "_End") (setq undoOpen nil))))

  (defun *error* (msg)
    (cperp:finish)
    (if (and msg (not (member msg '("Function cancelled" "quit / exit abort"))))
      (princ (strcat "\nError: " msg))
      (princ "\nCancelled."))
    (princ))

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
        tmpEnts '())
  (setvar "CMDECHO" 0)
  (command "._UNDO" "_Begin")
  (setq undoOpen T)
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

  ;; --- properties to give the offset polylines -------------------------
  (setq srcData  (entget crv)
        srcLayer (cdr (assoc 8 srcData))
        srcColor (cperp:color srcData)
        srcLtype (cond ((cdr (assoc 6 srcData))) ("BYLAYER"))
        srcLw    (cond ((cdr (assoc 370 srcData))) (-1))
        srcLts   (cond ((cdr (assoc 48 srcData))) (1.0)))

  ;; --- 2. click to set direction (START/FINISH) and offset side -------
  ;; The side is measured against the curve's own direction, so it stays
  ;; the same side whichever end the traversal starts from.
  (setvar "OSMODE" 0)
  (setq click nil)
  (while (null click)
    (setq click (getpoint "\nClick to pick direction / offset side: "))
    (cond
      ((null click)
       (princ "\nA point is required - click one side of the curve."))
      ((null (setq tng (cperp:tangent crv click)))
       (princ "\nCannot read the curve direction there - click elsewhere.")
       (setq click nil))
      (t
       ;; signed distance from the curve's tangent line at the projection
       (setq cross (- (* (car tng)  (- (cadr click)
                                       (cadr (trans (vlax-curve-getClosestPointTo
                                                      crv (trans click 1 0))
                                                    0 1))))
                      (* (cadr tng) (- (car click)
                                       (car (trans (vlax-curve-getClosestPointTo
                                                     crv (trans click 1 0))
                                                   0 1)))))
             fuzz  (max 1e-8 (* tot 1e-6)))
       (if (< (abs cross) fuzz)
         (progn
           (princ "\nThat point is on the curve - click clearly to one side.")
           (setq click nil))))))

  (setq side (if (>= cross 0.0) 1.0 -1.0)
        rev  (> (distance click sp) (distance click ep)))

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
  ;; path is nil in round 1, meaning "sample the curve itself"; later
  ;; rounds sample the polyline the previous round built.
  (setq path  nil
        again "Yes"
        iter  0
        total 0)

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

    ;; base points: along the curve itself in round 1 (by true arc
    ;; length), along the previous round's polyline after that
    (setq basePts (if path (cperp:sample path n) (cperp:curve-pts crv n rev)))

    ;; --- length per point + build the new perpendicular points -------
    ;; usedBases collects the base of each created point so bases and
    ;; new points stay paired even when a point is skipped; idxs records
    ;; each created point's position so U returns to the right prompt
    ;; even across skipped points.
    (setvar "CLAYER" "PERPPTS-TEMP")
    (setq newPts '() usedBases '() idxs '() guideEnts '() i 0)
    (while (< i n)
      (setq base (nth i basePts)
            nrm  (cperp:normal crv base side))
      (cond
        ;; no readable tangent under this point - skip it rather than
        ;; place the offset in an arbitrary direction
        ((null nrm)
         (princ (strcat "\nSkipping point " (itoa (1+ i))
                        ": the curve direction cannot be read there."))
         (setq i (1+ i)))
        (t
         (initget 6 "Undo")
         (setq len (getdist (strcat "\nLength for point " (itoa (1+ i))
                                    " of " (itoa n)
                                    (if lastLen
                                      (strcat " <" (rtos lastLen) ">")
                                      "")
                                    " [Undo]: ")))
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
                      idxs      (cdr idxs)))
              (princ "\nNothing to undo - this is the first point.")))
           ((null len)
            (princ "\nA length is required."))
           (t
            (setq lastLen len
                  np      (list (+ (car base)  (* len (car nrm)))
                                (+ (cadr base) (* len (cadr nrm)))
                                (caddr base)))
            (setq newPts    (cons np newPts)
                  usedBases (cons base usedBases)
                  idxs      (cons i idxs))
            (command "._POINT" np)
            (setq guideEnts (cons (entlast) guideEnts)
                  tmpEnts   (cons (entlast) tmpEnts))
            (setq i (1+ i)))))))
    (setq newPts    (reverse newPts)
          usedBases (reverse usedBases))

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

    ;; --- erase this round's point guides -----------------------------
    (foreach e guideEnts (cperp:kill e))
    (setq guideEnts nil)

    ;; --- remember the dimensions to draw -----------------------------
    ;; each pair runs along the curve normal at the base point's
    ;; projection, so the dimension reads perpendicular to the ORIGINAL
    ;; curve whichever polyline the base point sits on
    (setq i 0)
    (while (< i (length newPts))
      (setq dimPairs (cons (list (nth i usedBases) (nth i newPts)) dimPairs)
            i        (1+ i)))
    (setq total (+ total (length newPts)))

    ;; the polyline just built becomes the path for the next round
    (setq path newPts)

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

(princ "\ncperp_points.lsp loaded.  Type CPERPPTS to run.")
(princ)
