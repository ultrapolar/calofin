;;; perp_points.lsp  --  AutoCAD 2018 (AutoLISP)
;;;
;;; Command: PERPPTS
;;;
;;; Splits a selected line into N equally-spaced points (both endpoints
;;; included), then for each division point creates a new point offset
;;; perpendicular to the line by a user-supplied length.  The new points
;;; are joined with a polyline, and an aligned dimension is drawn from
;;; each new point back to its base point on the line.
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
;;;   1. Select a LINE.
;;;   2. Click a point to set the direction:
;;;        - the line end nearest the click becomes START, the far end
;;;          FINISH, fixing the order the lengths are entered in;
;;;        - the side of the line the click lands on is the side the new
;;;          points are offset toward.
;;;   3. Enter how many values (points) are required  (>= 2).
;;;   4. Enter a length for each point, in order START -> FINISH.
;;;   5. Choose whether to repeat on the new polyline.  If so, enter a
;;;      new point count and repeat from step 4 with the new polyline as
;;;      the path.
;;;
;;; The offset side is fixed once from the direction click in step 2 and
;;; reused for every round, so all offsets stay on the same side of the
;;; original line and every dimension stays perpendicular to it.
;;;
;;; License: GPL-3.0-or-later
;;; ---------------------------------------------------------------------

;; --- helpers ---------------------------------------------------------

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

;; --- command ---------------------------------------------------------

(defun c:PERPPTS (/ *error* os ent edata p1 p2 pStart pFinish click
                    dx dy dlen ux uy cross nx ny sz
                    arlen hlen tailx taily ca sa bkx bky b1x b1y b2x b2y
                    arrowEnts path n basePts newPts guideEnts
                    len i base bx by np npx npy again iter p e)

  (defun *error* (msg)
    (if os (setvar "OSMODE" os))
    (if (and msg (not (member msg '("Function cancelled" "quit / exit abort"))))
      (princ (strcat "\nError: " msg)))
    (princ))

  ;; --- 1. select a line ------------------------------------------------
  (setq ent (entsel "\nSelect a line: "))
  (if (null ent)
    (progn (princ "\nNothing selected.") (exit)))
  (setq edata (entget (car ent)))
  (if (/= "LINE" (cdr (assoc 0 edata)))
    (progn (princ "\nSelected object is not a line.") (exit)))
  (setq p1 (cdr (assoc 10 edata))          ; line start point
        p2 (cdr (assoc 11 edata)))         ; line end point

  ;; --- 2. click to set direction (START/FINISH) and offset side -------
  (setq click (getpoint "\nClick to pick direction / offset side: "))
  (if (null click)
    (progn (princ "\nNo direction picked.") (exit)))

  ;; nearest endpoint to the click = START
  (if (<= (distance click p1) (distance click p2))
    (setq pStart p1 pFinish p2)
    (setq pStart p2 pFinish p1))

  ;; unit vector along the line, START -> FINISH
  (setq dx   (- (car pFinish) (car pStart))
        dy   (- (cadr pFinish) (cadr pStart))
        dlen (sqrt (+ (* dx dx) (* dy dy))))
  (if (equal dlen 0.0 1e-9)
    (progn (princ "\nLine has zero length.") (exit)))
  (setq ux (/ dx dlen)
        uy (/ dy dlen))

  ;; perpendicular unit vector, chosen toward the clicked side.  This is
  ;; fixed for the whole command: every offset and dimension in every
  ;; round is measured along this direction, i.e. perpendicular to the
  ;; ORIGINAL line -- never to a later polyline.
  ;; cross = ux*(cy-sy) - uy*(cx-sx); >0 => click is on the left.
  (setq cross (- (* ux (- (cadr click) (cadr pStart)))
                 (* uy (- (car click)  (car pStart)))))
  (if (>= cross 0.0)
    (setq nx (- uy) ny ux)          ; left normal
    (setq nx uy     ny (- ux)))     ; right normal

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
  (setq arrowEnts '())
  ;; shaft
  (entmake (list '(0 . "LINE") '(62 . 1)
                 (list 10 tailx taily sz)
                 (list 11 (car pStart) (cadr pStart) sz)))
  (setq arrowEnts (cons (entlast) arrowEnts))
  ;; two arrowhead barbs meeting at the tip (START)
  (entmake (list '(0 . "LINE") '(62 . 1)
                 (list 10 (car pStart) (cadr pStart) sz)
                 (list 11 b1x b1y sz)))
  (setq arrowEnts (cons (entlast) arrowEnts))
  (entmake (list '(0 . "LINE") '(62 . 1)
                 (list 10 (car pStart) (cadr pStart) sz)
                 (list 11 b2x b2y sz)))
  (setq arrowEnts (cons (entlast) arrowEnts))

  ;; --- offset rounds --------------------------------------------------
  (setq os (getvar "OSMODE"))
  (setvar "OSMODE" 0)                       ; no snapping while placing

  ;; the path the points are spaced along.  Round 1 uses the original
  ;; line; each later round uses the polyline the previous round built.
  (setq path  (list pStart pFinish)
        again "Yes"
        iter  0)

  (while (= again "Yes")
    (setq iter (1+ iter))

    ;; --- how many values / points for this round ---------------------
    (setq n (getint (strcat "\nRound " (itoa iter)
                            " - how many values (points) are required? ")))
    (if (or (null n) (< n 2))
      (progn (princ "\nNeed at least 2 points.")
             (foreach e arrowEnts (if e (entdel e)))
             (setvar "OSMODE" os)
             (exit)))

    ;; base points, equally spaced along the current path.  The offset
    ;; side (nx,ny) was fixed from the direction click and is reused for
    ;; every round, so all rounds offset to the same side.
    (setq basePts (perp:sample path n))

    ;; --- length per point + build the new perpendicular points -------
    (setq newPts '() guideEnts '() i 0)
    (foreach base basePts
      (setq len (getdist (strcat "\nLength for point " (itoa (1+ i))
                                 " of " (itoa n) ": ")))
      (if (null len)
        (progn (foreach e guideEnts (if e (entdel e)))
               (foreach e arrowEnts (if e (entdel e)))
               (setvar "OSMODE" os)
               (exit)))
      (setq bx  (car base)
            by  (cadr base)
            npx (+ bx (* len nx))
            npy (+ by (* len ny))
            np  (list npx npy (caddr base)))
      (setq newPts (cons np newPts))
      ;; create a temporary POINT node at the new location as a guide
      (command "._POINT" np)
      (setq guideEnts (cons (entlast) guideEnts))
      (setq i (1+ i)))
    (setq newPts (reverse newPts))

    ;; --- connect the new points with a polyline ----------------------
    (command "._PLINE")
    (foreach p newPts (command p))
    (command "")

    ;; --- erase this round's point guides -----------------------------
    (foreach e guideEnts (if e (entdel e)))

    ;; --- aligned dimension from each new point to its base point ------
    ;; np = base + len*(nx,ny), so the dimension line always runs along
    ;; the fixed normal, i.e. perpendicular to the ORIGINAL line, no
    ;; matter which polyline `base` sits on.
    (setq i 0)
    (while (< i n)
      (setq base (nth i basePts)
            np   (nth i newPts))
      (command "._DIMALIGNED" base np np)   ; dim line through the new pt
      (setq i (1+ i)))

    ;; the polyline just built becomes the path for the next round
    (setq path newPts)

    ;; --- repeat? -----------------------------------------------------
    (initget "Yes No")
    (setq again (getkword "\nRepeat on the new polyline? [Yes/No] <No>: "))
    (if (null again) (setq again "No")))

  ;; --- clean up the direction arrow -----------------------------------
  (foreach e arrowEnts (if e (entdel e)))

  (setvar "OSMODE" os)
  (princ (strcat "\nDone: " (itoa iter)
                 " offset round(s), polylines and dimensions created."))
  (princ))

(princ "\nperp_points.lsp loaded.  Type PERPPTS to run.")
(princ)
