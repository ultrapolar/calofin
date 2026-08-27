;;; ===================================================================
;;; BPCALLOUT.lsp  --  ring bad points and write the callout naming them
;;; -------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Command:  BPCALLOUT
;;;
;;; Click every point that is bad, one after another, as many as you
;;; like; press Enter when done.  Each click:
;;;   * snaps to the nearest survey point within *BP-SNAP* of the pick
;;;     (an "ab_pt" INSERT on any layer, any other INSERT on the POINTS
;;;     layer, or a plain POINT on the POINTS layer - the same
;;;     classifier the rest of the toolset uses),
;;;   * draws a *BP-RADIUS* circle on the FGStep layer centered on
;;;     that point, and
;;;   * reads what the point is called from the block's "number"
;;;     attribute, the name the drawing itself carries.
;;; After the last click you place one TEXT that names them all:
;;;
;;;   "Pt.12 is bad"                            (one point)
;;;   "Pt.12 and Pt.15 are bad"                 (two)
;;;   "Pt.12, Pt.15 and Pt.20 are bad"          (three or more)
;;;
;;; A click that lands nowhere near a survey point is still ringed -
;;; exactly where you clicked - and reported as "Pt.?", so a stray
;;; shot with no block under it can be called out too.  Clicking a
;;; ringed point AGAIN un-rings it: the circle is erased and the point
;;; leaves the callout - reselect a point to undo it.
;;;
;;; Versioning: see tools/release_lisp.py at the repo root.  It reads
;;; *bpcallout-version* below and stamps a dated, REV-numbered twin of
;;; this file into releases/.
;;;
;;; Assumes drawing units are INCHES (architectural).  Adjust the
;;; constants below for other setups.
;;; ===================================================================

;; ---- configuration -------------------------------------------------
(setq *bpcallout-version* "v1.4")   ; announced on load; release_lisp.py
                                    ; reads this banner and stamps the
                                    ; dated twin in releases/ from it
(setq *BP-LAYER*       "FGStep")    ; layer the rings and the callout
                                    ; text go on - the same layer LHD
                                    ; puts its miss rings on
(setq *BP-RADIUS*      5.0)         ; ring RADIUS (5 inches); halve it
                                    ; here if a 5" diameter is wanted
(setq *BP-SNAP*        12.0)        ; a pick within this of a survey
                                    ; point rings THAT point; farther
                                    ; away, the pick itself is ringed
                                    ; and named "?"
(setq *BP-TEXT-HGT*    6.0)         ; callout text height
(setq *BP-POINT-BLOCK* "ab_pt")     ; block name whose INSERTs mark
                                    ; points wherever they sit
(setq *BP-POINT-LAYER* "POINTS")    ; layer whose POINTs/INSERTs are
                                    ; always points
(setq *BP-PT-TAG*      "number")    ; attribute tag on the point block
                                    ; naming the point, as in "Pt.17"
(setq *BP-EXACT-EPS*   0.001)       ; two picks this close land on the
                                    ; same spot - the second un-rings it

;; ---- helpers -------------------------------------------------------

;; Flat XY distance, whatever Z the inputs carry.
(defun bp:dist (a b)
  (distance (list (car a) (cadr a)) (list (car b) (cadr b))))

;; Create the output layer, or make sure it is on, thawed, unlocked.
(defun bp:ensure-layer (name colour / rec ed flags col fixed)
  (if (not (tblsearch "LAYER" name))
    (entmakex (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                    '(100 . "AcDbLayerTableRecord")
                    (cons 2 name) '(70 . 0) (cons 62 colour)
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
          (princ (strcat "\nBPCALLOUT: layer " name
                         " was off, frozen or locked - restored so the"
                         " result is visible.")))))))

;; The name carried by a point block, read from its *BP-PT-TAG*
;; attribute; when the block has no such attribute, the first
;; attribute whose value reads as a number is taken instead (survey
;; exports do not all use the ab_pt tag).  nil when neither exists.
(defun bp:block-number (en / sub ed val fall v)
  (setq sub (entnext en) val nil fall nil)
  (while (and sub
              (setq ed (entget sub))
              (= "ATTRIB" (cdr (assoc 0 ed))))
    (setq v (cdr (assoc 1 ed)))
    (if (and (null val)
             (cdr (assoc 2 ed))
             (= (strcase (cdr (assoc 2 ed))) (strcase *BP-PT-TAG*)))
      (setq val v))
    (if (and (null fall) v (distof v 2))
      (setq fall v))
    (setq sub (entnext sub)))
  (if val val fall))

;; Every survey point in the drawing, as ((x y) . name) pairs.  What
;; counts as a point matches LHD's classifier: an *BP-POINT-BLOCK*
;; INSERT anywhere, any other INSERT on the *BP-POINT-LAYER* layer,
;; or a plain POINT on that layer.  A point with no readable number
;; is carried as "?" so it can still be ringed and reported.
(defun bp:collect-points (/ ss i en ed typ p nm out)
  (setq out nil
        ss  (ssget "_X" '((0 . "INSERT,POINT"))))
  (if ss
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq en  (ssname ss i)
              ed  (entget en)
              typ (cdr (assoc 0 ed))
              p   (cdr (assoc 10 ed)))
        (cond
          ((= typ "INSERT")
           (if (or (= (strcase (cdr (assoc 2 ed)))
                      (strcase *BP-POINT-BLOCK*))
                   (= (strcase (cdr (assoc 8 ed)))
                      (strcase *BP-POINT-LAYER*)))
             (progn
               (setq nm (bp:block-number en))
               (setq out (cons (cons (list (car p) (cadr p))
                                     (if (and nm (/= nm "")) nm "?"))
                               out)))))
          ((= typ "POINT")
           (if (= (strcase (cdr (assoc 8 ed)))
                  (strcase *BP-POINT-LAYER*))
             (setq out (cons (cons (list (car p) (cadr p)) "?") out)))))
        (setq i (1+ i)))))
  out)

;; The survey point nearest to pick PK, when one sits within *BP-SNAP*
;; of it; nil otherwise.  Returns the ((x y) . name) pair.
(defun bp:nearest-point (pk cands / best bd c d)
  (setq best nil bd nil)
  (foreach c cands
    (setq d (bp:dist pk (car c)))
    (if (and (<= d *BP-SNAP*) (or (null bd) (< d bd)))
      (setq best c bd d)))
  best)

;; The picked-list entry a new click lands on, when it lands on one:
;; either its snapped centre CTR is (as good as) an already-ringed
;; spot, or - for a pick with no survey point under it - the raw pick
;; PK is inside an existing ring.  Entries are (ctr name ring-ename);
;; nil when the click is somewhere new.
(defun bp:ringed-at (pk ctr picked / hit bd q d)
  (setq hit nil)
  (foreach q picked
    (if (< (bp:dist ctr (car q)) *BP-EXACT-EPS*) (setq hit q)))
  (if (null hit)
    (progn                              ; nearest ring the pick sits in
      (setq bd nil)
      (foreach q picked
        (setq d (bp:dist pk (car q)))
        (if (and (<= d *BP-RADIUS*) (or (null bd) (< d bd)))
          (setq hit q bd d)))))
  hit)

;; Remove the entry whose ring is ENT from LST, keeping the order.
(defun bp:drop-entry (ent lst / out q)
  (foreach q lst (if (not (eq (caddr q) ent)) (setq out (cons q out))))
  (reverse out))

;; The callout sentence: "Pt.12 is bad", "Pt.12 and Pt.15 are bad",
;; "Pt.12, Pt.15 and Pt.20 are bad" - commas between all but the last
;; pair, "and" before the last, is/are by count.
(defun bp:phrase (names / n s i)
  (setq n (length names))
  (cond
    ((= n 0) "")
    ((= n 1) (strcat "Pt." (car names) " is bad"))
    (T
     (setq s (strcat "Pt." (car names)) i 1)
     (while (< i (1- n))
       (setq s (strcat s ", Pt." (nth i names))
             i (1+ i)))
     (strcat s " and Pt." (nth (1- n) names) " are bad"))))

;; Ring one bad point.
(defun bp:draw-ring (ctr)
  (entmakex (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                  (cons 8 *BP-LAYER*) '(100 . "AcDbCircle")
                  (cons 10 (list (car ctr) (cadr ctr) 0.0))
                  (cons 40 *BP-RADIUS*))))

;; Write the callout text at P.
(defun bp:draw-text (p str)
  (entmakex (list '(0 . "TEXT") '(100 . "AcDbEntity")
                  (cons 8 *BP-LAYER*) '(100 . "AcDbText")
                  (cons 10 (list (car p) (cadr p) 0.0))
                  (cons 40 *BP-TEXT-HGT*)
                  (cons 1 str))))

;; ---- command -------------------------------------------------------
;; NOTE: no local here may be named after a function this routine
;; calls - an AutoLISP local SHADOWS the function of the same name for
;; the whole call, so a local called "last" turns every (last ...) in
;; the body into "no function definition: LAST" at runtime.
(defun c:BPCALLOUT (/ *error* undo-open cands pk hit ctr nm old picked names
                      txtpt phrase lastpt)
  ;; the rings and the callout are one undo group, so a run backed out
  ;; halfway takes one U rather than one per circle; the group is only
  ;; closed if it was opened (STANDARDS section 5)
  (defun *error* (msg)
    (if undo-open (command "_.UNDO" "_End"))
    (setq undo-open nil)
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nBPCALLOUT error: " msg)))
    (princ))
  (command "_.UNDO" "_Begin")
  (setq undo-open T)

  (princ (strcat "\nBPCALLOUT " *bpcallout-version*))
  (setq cands (bp:collect-points))
  (if cands
    (princ (strcat "\n" (itoa (length cands)) " survey point(s) found;"
                   " a click within " (rtos *BP-SNAP* 4 0)
                   " snaps to the nearest one."))
    (princ (strcat "\nNo survey points found in the drawing - clicks"
                   " will be ringed where picked and named \"?\".")))

  (setq picked nil)
  (while (setq pk (getpoint
                    "\nClick a bad point (a ringed one un-rings it, Enter when done): "))
    (setq hit (bp:nearest-point pk cands))
    (if hit
      (setq ctr (car hit) nm (cdr hit))
      (setq ctr (list (car pk) (cadr pk)) nm "?"))
    (setq old (bp:ringed-at pk ctr picked))
    (if old
      (progn                            ; reselecting a point undoes it
        (if (and (caddr old) (entget (caddr old)))
          (entdel (caddr old)))
        (setq picked (bp:drop-entry (caddr old) picked))
        (princ (strcat "\n  Pt." (cadr old) " un-ringed.")))
      (progn
        (bp:ensure-layer *BP-LAYER* 1)
        (setq picked (cons (list ctr nm (bp:draw-ring ctr)) picked))
        (if hit
          (princ (strcat "\n  Pt." nm " ringed."))
          (princ (strcat "\n  No survey point within "
                         (rtos *BP-SNAP* 4 0)
                         " of the pick - ringed where clicked, as"
                         " Pt.?."))))))

  (if (null picked)
    (princ "\nBPCALLOUT: nothing picked - nothing drawn.")
    (progn
      (setq picked (reverse picked)             ; back to click order
            names  (mapcar 'cadr picked)
            phrase (bp:phrase names)
            lastpt (car (last picked)))
      (setq txtpt (getpoint (strcat "\nPlace the callout text <beside"
                                    " the last ring>: ")))
      (if (null txtpt)                          ; Enter: tuck it beside
        (setq txtpt (list (+ (car lastpt) (* 2.0 *BP-RADIUS*))
                          (- (cadr lastpt) (* 2.0 *BP-RADIUS*)))))
      (bp:draw-text txtpt phrase)
      (princ (strcat "\nBPCALLOUT: " (itoa (length picked))
                     " point(s) ringed on layer " *BP-LAYER*
                     ";  \"" phrase "\""))))
  (if undo-open (command "_.UNDO" "_End"))
  (setq undo-open nil)
  (princ))

(princ (strcat "\nBPCALLOUT " *bpcallout-version*
               " loaded. Command: BPCALLOUT (ring bad points and write"
               " the callout)."))
(princ)
