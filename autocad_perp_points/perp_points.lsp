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
;;; Workflow
;;;   1. Select a LINE.
;;;   2. Enter how many values (points) are required  (>= 2).
;;;   3. Click a point to set the direction:
;;;        - the line end nearest the click becomes START, the far end
;;;          FINISH, fixing the order the lengths are entered in;
;;;        - the side of the line the click lands on is the side the new
;;;          points are offset toward.
;;;   4. Enter a length for each point, in order START -> FINISH.
;;;
;;; License: GPL-3.0-or-later
;;; ---------------------------------------------------------------------

(defun c:PERPPTS (/ *error* os ent edata p1 p2 pStart pFinish n click
                    dx dy dlen ux uy px py cross nx ny i t base bx by
                    len np npx npy basePts newPts pline)

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

  ;; --- 2. how many values / points ------------------------------------
  (setq n (getint "\nHow many values (points) are required? "))
  (if (or (null n) (< n 2))
    (progn (princ "\nNeed at least 2 points.") (exit)))

  ;; --- 3. click to set direction (START/FINISH) and offset side -------
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

  ;; perpendicular unit vector, chosen toward the clicked side.
  ;; cross = ux*(cy-sy) - uy*(cx-sx); >0 => click is on the left.
  (setq cross (- (* ux (- (cadr click) (cadr pStart)))
                 (* uy (- (car click)  (car pStart)))))
  (if (>= cross 0.0)
    (setq nx (- uy) ny ux)          ; left normal
    (setq nx uy     ny (- ux)))     ; right normal

  ;; --- build the base points (START..FINISH, equally spaced) ----------
  (setq basePts '() i 0)
  (while (< i n)
    (setq t  (/ (float i) (float (1- n)))
          bx (+ (car pStart)  (* t (- (car pFinish)  (car pStart))))
          by (+ (cadr pStart) (* t (- (cadr pFinish) (cadr pStart)))))
    (setq basePts (cons (list bx by (caddr pStart)) basePts))
    (setq i (1+ i)))
  (setq basePts (reverse basePts))

  ;; --- 4. length per point + build the new perpendicular points -------
  (setq os (getvar "OSMODE"))
  (setvar "OSMODE" 0)                       ; no snapping while placing
  (setq newPts '() i 0)
  (foreach base basePts
    (setq len (getdist (strcat "\nLength for point " (itoa (1+ i))
                               " of " (itoa n) ": ")))
    (if (null len) (progn (setvar "OSMODE" os) (exit)))
    (setq bx  (car base)
          by  (cadr base)
          npx (+ bx (* len nx))
          npy (+ by (* len ny))
          np  (list npx npy (caddr base)))
    (setq newPts (cons np newPts))
    ;; create a POINT node at the new location
    (command "._POINT" np)
    (setq i (1+ i)))
  (setq newPts (reverse newPts))

  ;; --- connect the new points with a polyline -------------------------
  (command "._PLINE")
  (foreach p newPts (command p))
  (command "")

  ;; --- aligned dimension from each new point to its base point --------
  (setq i 0)
  (while (< i n)
    (setq base (nth i basePts)
          np   (nth i newPts))
    (command "._DIMALIGNED" base np np)     ; dim line through the new pt
    (setq i (1+ i)))

  (setvar "OSMODE" os)
  (princ (strcat "\nDone: " (itoa n)
                 " perpendicular points, connecting polyline and dimensions created."))
  (princ))

(princ "\nperp_points.lsp loaded.  Type PERPPTS to run.")
(princ)
