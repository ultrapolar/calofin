;;; ===================================================================
;;; BPCALLOUT.lsp  --  ring bad points and write the callout naming them
;;; -------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Command:  BPCALLOUT
;;;
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;
;;; Click every point that is bad, one after another, as many as you
;;; like; press Enter when done.  Each click:
;;;   * snaps to the nearest survey point within *BP-SNAP* of the pick
;;;     (an "ab_pt" INSERT on any layer, any other INSERT on the POINTS
;;;     layer, or a plain POINT on the POINTS layer - the same
;;;     classifier the rest of the toolset uses),
;;;   * draws a *BP-RADIUS* circle on the *BP-LAYER* layer centered on
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
;;; leaves the callout - reselect a point to undo it.  A click that
;;; snaps to a DIFFERENT survey point never un-rings a neighbour it
;;; merely lands close to (v1.7 did, so two points under 10" apart
;;; could not both be ringed); only a click with no survey point under
;;; it is read against the rings it sits inside.
;;;
;;; Versioning: see tools/release_lisp.py at the repo root.  It reads
;;; *bpcallout-version* below and stamps a dated, REV-numbered twin of
;;; this file into releases/.
;;;
;;; Assumes drawing units are INCHES (architectural).  Every knob -
;;; layer and its colour, ring size, snap reach, text height, the
;;; wording of the callout, what counts as a survey point - is in the
;;; configuration block right below, each with its explanation.
;;; ===================================================================

;; ---- configuration -------------------------------------------------
;; Every knob the routine has, in one place, so nothing below this
;; block needs touching to adapt it.  Change a value here, or (setq ...)
;; it after loading from a startup file.  Distances are DRAWING UNITS -
;; inches in this shop's architectural drawings.
(setq *bpcallout-version* "v1.8")   ; announced on load; release_lisp.py
                                    ; reads this banner and stamps the
                                    ; dated twin in releases/ from it
;; -- where the marks go
(setq *BP-LAYER*       "FGStep")    ; layer the rings and the callout
                                    ; text land on - the same layer LHD
                                    ; puts its miss rings on.  Created
                                    ; when the drawing lacks it; thawed,
                                    ; unlocked and switched on when it
                                    ; is there but unusable
(setq *BP-LAYER-COLOR* 1)           ; ACI colour that layer is CREATED
                                    ; with (1 = red).  A layer already
                                    ; in the drawing keeps its own
;; -- the rings
(setq *BP-RADIUS*      5.0)         ; ring RADIUS (5" = a 10" circle);
                                    ; halve it if a 5" DIAMETER is
                                    ; wanted.  Also how far an un-ring
                                    ; click reaches: a click inside a
                                    ; ring that has no survey point
                                    ; under it removes that ring
(setq *BP-SNAP*        12.0)        ; a pick within this of a survey
                                    ; point rings THAT point - the
                                    ; nearest one when several qualify;
                                    ; farther away, the pick itself is
                                    ; ringed and named *BP-UNKNOWN*
(setq *BP-EXACT-EPS*   0.001)       ; two ring centres this close are
                                    ; the same spot, so a second click
                                    ; on a ringed survey point un-rings
                                    ; it rather than ringing it twice
;; -- the callout text
(setq *BP-TEXT-HGT*    6.0)         ; TEXT height of the callout
(setq *BP-TEXT-GAP*    10.0)        ; Enter at the text prompt tucks the
                                    ; callout this far to the right of
                                    ; AND below the last ring's centre
(setq *BP-PT-PREFIX*   "Pt.")       ; how a point is named, in the
                                    ; callout and on the command line:
                                    ; the prefix + its number, "Pt.12"
(setq *BP-TAIL-ONE*    " is bad")   ; what follows the name when ONE
                                    ; point was ringed: "Pt.12 is bad"
(setq *BP-TAIL-MANY*   " are bad")  ; ...and when two or more were:
                                    ; "Pt.12, Pt.15 and Pt.20 are bad"
(setq *BP-UNKNOWN*     "?")         ; the number given to a ring with
                                    ; no readable survey point under
                                    ; it, so it still reads "Pt.? is
                                    ; bad" rather than vanishing
;; -- what counts as a survey point.  The classifier is shared with
;;    LHD and CDCALLOUT: change it in all three or the tools disagree
(setq *BP-POINT-BLOCK* "ab_pt")     ; block name whose INSERTs mark
                                    ; points wherever they sit
(setq *BP-POINT-LAYER* "POINTS")    ; layer whose POINTs and INSERTs
                                    ; are always points, whatever block
(setq *BP-PT-TAG*      "number")    ; attribute tag on the point block
                                    ; naming the point.  A block without
                                    ; it lends its first attribute that
                                    ; reads as a number instead

;; ---- helpers -------------------------------------------------------

;; Every survey point in the drawing, as ((x y) . name) pairs.  What
;; counts as a point matches LHD's classifier: an *BP-POINT-BLOCK*
;; INSERT anywhere, any other INSERT on the *BP-POINT-LAYER* layer,
;; or a plain POINT on that layer.  A point with no readable number
;; is carried as *BP-UNKNOWN* ("?") so it can still be ringed and
;; reported.
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
               (setq nm (cal:block-number en *BP-PT-TAG*))
               (setq out (cons (cons (list (car p) (cadr p))
                                     (if (and nm (/= nm "")) nm
                                       *BP-UNKNOWN*))
                               out)))))
          ((= typ "POINT")
           (if (= (strcase (cdr (assoc 8 ed)))
                  (strcase *BP-POINT-LAYER*))
             (setq out (cons (cons (list (car p) (cadr p)) *BP-UNKNOWN*)
                             out)))))
        (setq i (1+ i)))))
  out)

;; The survey point nearest to pick PK, when one sits within *BP-SNAP*
;; of it; nil otherwise.  Returns the ((x y) . name) pair.
(defun bp:nearest-point (pk cands / best bd c d)
  (setq best nil bd nil)
  (foreach c cands
    (setq d (cal:dist pk (car c)))
    (if (and (<= d *BP-SNAP*) (or (null bd) (< d bd)))
      (setq best c bd d)))
  best)

;; The picked-list entry a new click lands on, when it lands on one:
;; either its snapped centre CTR is (as good as) an already-ringed
;; spot, or - ONLY for a pick with no survey point under it, SNAPPED
;; nil - the raw pick PK is inside an existing ring.  A pick that did
;; snap to a survey point is that point and nothing else: v1.7 read it
;; against the rings too, so a click meant for a point 8" from a ringed
;; one landed inside the 5" ring and un-ringed the neighbour instead.
;; Entries are (ctr name ring-ename); nil when the click is somewhere
;; new.
(defun bp:ringed-at (pk ctr picked snapped / hit bd q d)
  (setq hit nil)
  (foreach q picked
    (if (< (cal:dist ctr (car q)) *BP-EXACT-EPS*) (setq hit q)))
  (if (and (null hit) (not snapped))
    (progn                              ; nearest ring the pick sits in
      (setq bd nil)
      (foreach q picked
        (setq d (cal:dist pk (car q)))
        (if (and (<= d *BP-RADIUS*) (or (null bd) (< d bd)))
          (setq hit q bd d)))))
  hit)

;; Remove the entry whose ring is ENT from LST, keeping the order.
(defun bp:drop-entry (ent lst / out q)
  (foreach q lst (if (not (eq (caddr q) ent)) (setq out (cons q out))))
  (reverse out))

;; The callout sentence: "Pt.12 is bad", "Pt.12 and Pt.15 are bad",
;; "Pt.12, Pt.15 and Pt.20 are bad" - commas between all but the last
;; pair, "and" before the last, is/are by count.  The name prefix and
;; the two sentence tails are the *BP-PT-PREFIX* / *BP-TAIL-* knobs.
(defun bp:phrase (names / n s i)
  (setq n (length names))
  (cond
    ((= n 0) "")
    ((= n 1) (strcat *BP-PT-PREFIX* (car names) *BP-TAIL-ONE*))
    (T
     (setq s (strcat *BP-PT-PREFIX* (car names)) i 1)
     (while (< i (1- n))
       (setq s (strcat s ", " *BP-PT-PREFIX* (nth i names))
             i (1+ i)))
     (strcat s " and " *BP-PT-PREFIX* (nth (1- n) names)
             *BP-TAIL-MANY*))))

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
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (setq undo-open nil)
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nBPCALLOUT error: " msg)))
    (princ))
  ;; only when undo is recording - _Begin in a drawing with UNDO
  ;; off (bit 1 of UNDOCTL clear) errors out of the command
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn
      (command "_.UNDO" "_Begin")
      (setq undo-open T)))

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
      (setq ctr (list (car pk) (cadr pk)) nm *BP-UNKNOWN*))
    (setq old (bp:ringed-at pk ctr picked hit))
    (if old
      (progn                            ; reselecting a point undoes it
        (if (and (caddr old) (entget (caddr old)))
          (entdel (caddr old)))
        (setq picked (bp:drop-entry (caddr old) picked))
        (princ (strcat "\n  " *BP-PT-PREFIX* (cadr old)
                       " un-ringed.")))
      (progn
        (cal:ensure-layer *BP-LAYER* *BP-LAYER-COLOR*)
        (setq picked (cons (list ctr nm (bp:draw-ring ctr)) picked))
        (if hit
          (princ (strcat "\n  " *BP-PT-PREFIX* nm " ringed."))
          (princ (strcat "\n  No survey point within "
                         (rtos *BP-SNAP* 4 0)
                         " of the pick - ringed where clicked, as "
                         *BP-PT-PREFIX* *BP-UNKNOWN* "."))))))

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
        (setq txtpt (list (+ (car lastpt) *BP-TEXT-GAP*)
                          (- (cadr lastpt) *BP-TEXT-GAP*))))
      (bp:draw-text txtpt phrase)
      (princ (strcat "\nBPCALLOUT: " (itoa (length picked))
                     " point(s) ringed on layer " *BP-LAYER*
                     ";  \"" phrase "\""))))
  (if undo-open (command "_.UNDO" "_End"))
  (setq undo-open nil)
  (princ))

(defun c:BPCALLOUTVER ()
  (princ (strcat "\nBPCALLOUT " *bpcallout-version*))
  (princ))

(princ (strcat "\nBPCALLOUT " *bpcallout-version*
               " loaded. Command: BPCALLOUT (ring bad points and write"
               " the callout)."))
(princ)
