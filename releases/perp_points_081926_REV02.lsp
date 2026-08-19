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
;;;   1. Select a LINE (a polyline is also accepted, so work started in
;;;      an earlier session can be resumed).
;;;   2. Click a point to set the direction:
;;;        - the line end nearest the click becomes START, the far end
;;;          FINISH, fixing the order the lengths are entered in;
;;;        - the side of the line the click lands on is the side the new
;;;          points are offset toward.
;;;   3. Enter how many values (points) are required  (>= 2).
;;;   4. Enter a length for each point, in order START -> FINISH.
;;;      Press Enter to reuse the previous length when it repeats, or
;;;      type B (Back) to step back and re-enter the previous point
;;;      (U, the old keyword, is still accepted).
;;;   5. Choose whether to repeat on the new polyline.  If so, enter a
;;;      new point count and repeat from step 4 with the new polyline as
;;;      the path.
;;;   6. Pick the dimension style, STANDARD INCHES or SIDE STANDARD.
;;;      Every dimension is then drawn at once, on the DIMENSIONS layer.
;;;
;;; The offset side is fixed once from the direction click in step 2 and
;;; reused for every round, so all offsets stay on the same side of the
;;; original line and every dimension stays perpendicular to it.
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
(setq *perp-version* "v0.2")

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

;; make sure a layer exists and is usable (thawed, unlocked, on)
(defun perp:layer (nm col / en d)
  (if (setq en (tblobjname "LAYER" nm))
    (progn
      (setq d (entget en))
      ;; clear the frozen (1) and locked (4) bits
      (setq d (subst (cons 70 (logand (cdr (assoc 70 d)) (~ 5)))
                     (assoc 70 d) d))
      ;; a negative colour number means the layer is switched off
      (if (< (cdr (assoc 62 d)) 0)
        (setq d (subst (cons 62 (abs (cdr (assoc 62 d)))) (assoc 62 d) d)))
      (entmod d))
    (entmake (list '(0 . "LAYER")
                   '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord")
                   (cons 2 nm) '(70 . 0) (cons 62 col)
                   '(6 . "Continuous"))))
  nm)

;; --- command ---------------------------------------------------------

(defun c:PERPPTS (/ *error* perp:kill perp:finish
                    os ce pd clay cec celt celw celts cdim undoOpen tmpEnts
                    srcData srcLayer srcColor srcLtype srcLw srcLts
                    dimPairs dimStyle pr
                    sel ent etype verts p1 p2 pStart pFinish click
                    dx dy dlen ux uy cross fuzz nx ny sz
                    arlen hlen tailx taily ca sa bkx bky b1x b1y b2x b2y
                    path n lastN basePts newPts guideEnts total
                    len lastLen i base np again ans iter p e seg)

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
    (if ce   (setvar "CMDECHO" ce))
    (if undoOpen
      (progn (command "._UNDO" "_End") (setq undoOpen nil))))

  (defun *error* (msg)
    (perp:finish)
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

  ;; --- 2. click to set direction (START/FINISH) and offset side -------
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
  (perp:layer "PERPPTS-TEMP" 1)     ; guides, erased before the command ends
  (perp:layer "DIMENSIONS"   4)

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
    ;; every round, so all rounds offset to the same side.
    (setq basePts (perp:sample path n))

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

  ;; --- 5. dimension style, then draw every dimension ------------------
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
