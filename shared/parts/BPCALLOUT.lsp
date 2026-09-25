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
;;;   * snaps to the nearest survey point within bp:*snap* of the pick
;;;     (an "ab_pt" INSERT on any layer, any other INSERT on the POINTS
;;;     layer, or a plain POINT on the POINTS layer - the same
;;;     classifier the rest of the toolset uses),
;;;   * draws a bp:*radius* circle on the bp:*layer* layer centered on
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

;;; -------------------- version ---------------------------------------
(setq *bpcallout-version* "v1.12")   ; announced on load; release_lisp.py
                                    ; reads this banner and stamps the
                                    ; dated twin in releases/ from it

;;; -------------------- tunables --------------------------------------
;;; Every knob the routine has, in one place, so nothing below this
;;; block needs touching to adapt it.  Change a value here, or (setq ...)
;;; it after loading from a startup file.  Distances are DRAWING UNITS -
;;; inches in this shop's architectural drawings.

;; -- where the marks go
(setq bp:*layer* "FGStep")          ; layer the rings and the callout
                                    ; text land on - the same layer LHD
                                    ; puts its miss rings on.  Created
                                    ; when the drawing lacks it; thawed,
                                    ; unlocked and switched on when it
                                    ; is there but unusable
(setq bp:*layer-color* 1)           ; ACI colour that layer is CREATED
                                    ; with (1 = red).  A layer already
                                    ; in the drawing keeps its own

;; -- the rings
(setq bp:*radius* 5.0)              ; ring RADIUS (5" = a 10" circle);
                                    ; halve it if a 5" DIAMETER is
                                    ; wanted.  Also how far an un-ring
                                    ; click reaches: a click inside a
                                    ; ring that has no survey point
                                    ; under it removes that ring
(setq bp:*snap* 12.0)               ; a pick within this of a survey
                                    ; point rings THAT point - the
                                    ; nearest one when several qualify;
                                    ; farther away, the pick itself is
                                    ; ringed and named bp:*unknown*
(setq bp:*exact-eps* 0.001)         ; two ring centres this close are
                                    ; the same spot, so a second click
                                    ; on a ringed survey point un-rings
                                    ; it rather than ringing it twice

;; -- the callout text
(setq bp:*text-hgt* 6.0)            ; TEXT height of the callout
(setq bp:*text-gap* 10.0)           ; Enter at the text prompt tucks the
                                    ; callout this far to the right of
                                    ; AND below the last ring's centre
(setq bp:*pt-prefix* "Pt.")         ; how a point is named, in the
                                    ; callout and on the command line:
                                    ; the prefix + its number, "Pt.12"
(setq bp:*tail-one* " is bad")      ; what follows the name when ONE
                                    ; point was ringed: "Pt.12 is bad"
(setq bp:*tail-many* " are bad")    ; ...and when two or more were:
                                    ; "Pt.12, Pt.15 and Pt.20 are bad"
(setq bp:*unknown* "?")             ; the number given to a ring with
                                    ; no readable survey point under
                                    ; it, so it still reads "Pt.? is
                                    ; bad" rather than vanishing

;; -- what counts as a survey point.  The classifier is shared with
;;    LHD and CDCALLOUT: change it in all three or the tools disagree
(setq bp:*point-block* "ab_pt")     ; block name whose INSERTs mark
                                    ; points wherever they sit
(setq bp:*point-layer* "POINTS")    ; layer whose POINTs and INSERTs
                                    ; are always points, whatever block
(setq bp:*pt-tag* "number")         ; attribute tag on the point block
                                    ; naming the point.  A block without
                                    ; it lends its first attribute that
                                    ; reads as a number instead

;;; -------------------- helpers ----------------------------------------

;; Every survey point in the drawing, as ((x y) . name) pairs.  What
;; counts as a point matches LHD's classifier: an bp:*point-block*
;; INSERT anywhere, any other INSERT on the bp:*point-layer* layer,
;; or a plain POINT on that layer.  A point with no readable number
;; is carried as bp:*unknown* ("?") so it can still be ringed and
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
                      (strcase bp:*point-block*))
                   (= (strcase (cdr (assoc 8 ed)))
                      (strcase bp:*point-layer*)))
             (progn
               (setq nm (cal:block-number en bp:*pt-tag*))
               (setq out (cons (cons (list (car p) (cadr p))
                                     (if (and nm (/= nm "")) nm
                                       bp:*unknown*))
                               out)))))
          ((= typ "POINT")
           (if (= (strcase (cdr (assoc 8 ed)))
                  (strcase bp:*point-layer*))
             (setq out (cons (cons (list (car p) (cadr p)) bp:*unknown*)
                             out)))))
        (setq i (1+ i)))))
  out)

;; The survey point nearest to pick PK, when one sits within bp:*snap*
;; of it; nil otherwise.  Returns the ((x y) . name) pair.
(defun bp:nearest-point (pk cands / best bd c d)
  (setq best nil bd nil)
  (foreach c cands
    (setq d (cal:dist pk (car c)))
    (if (and (<= d bp:*snap*) (or (null bd) (< d bd)))
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
    (if (< (cal:dist ctr (car q)) bp:*exact-eps*) (setq hit q)))
  (if (and (null hit) (not snapped))
    (progn                              ; nearest ring the pick sits in
      (setq bd nil)
      (foreach q picked
        (setq d (cal:dist pk (car q)))
        (if (and (<= d bp:*radius*) (or (null bd) (< d bd)))
          (setq hit q bd d)))))
  hit)

;; Remove the entry whose ring is ENT from LST, keeping the order.
(defun bp:drop-entry (ent lst / out q)
  (foreach q lst (if (not (eq (caddr q) ent)) (setq out (cons q out))))
  (reverse out))

;; The callout sentence: "Pt.12 is bad", "Pt.12 and Pt.15 are bad",
;; "Pt.12, Pt.15 and Pt.20 are bad" - commas between all but the last
;; pair, "and" before the last, is/are by count.  The name prefix and
;; the two sentence tails are the bp:*pt-prefix* / bp:*tail-* knobs.
(defun bp:phrase (names / n s i)
  (setq n (length names))
  (cond
    ((= n 0) "")
    ((= n 1) (strcat bp:*pt-prefix* (car names) bp:*tail-one*))
    (T
     (setq s (strcat bp:*pt-prefix* (car names)) i 1)
     (while (< i (1- n))
       (setq s (strcat s ", " bp:*pt-prefix* (nth i names))
             i (1+ i)))
     (strcat s " and " bp:*pt-prefix* (nth (1- n) names)
             bp:*tail-many*))))

;; Ring one bad point.
(defun bp:draw-ring (ctr)
  (entmakex (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                  (cons 8 bp:*layer*) '(100 . "AcDbCircle")
                  (cons 10 (list (car ctr) (cadr ctr) 0.0))
                  (cons 40 bp:*radius*))))

;; How far the current UCS is turned from the world X axis, so the
;; callout reads along the UCS the drafter is drawing in.  Taken off
;; the UCS X axis moved into the world -- not off UCSXDIR run back into
;; the UCS, which is (1 0 0) there however far the UCS is turned, so it
;; would always answer zero.  0 in the world UCS.
(defun bp:ucsang ( / v)
  (setq v (trans '(1.0 0.0 0.0) 1 0 T))
  (atan (cadr v) (car v)))

;; Write the callout text at P, a WORLD point.
(defun bp:draw-text (p str)
  (entmakex (list '(0 . "TEXT") '(100 . "AcDbEntity")
                  (cons 8 bp:*layer*) '(100 . "AcDbText")
                  (cons 10 (list (car p) (cadr p) 0.0))
                  (cons 40 bp:*text-hgt*)
                  (cons 50 (bp:ucsang))
                  (cons 1 str))))

;;; -------------------- the command ------------------------------------
;; NOTE: no local here may be named after a function this routine
;; calls - an AutoLISP local SHADOWS the function of the same name for
;; the whole call, so a local called "last" turns every (last ...) in
;; the body into "no function definition: LAST" at runtime.
(defun c:BPCALLOUT (/ *error* undo-open cands pk hit ctr nm old picked names
                      txtpt phrase lastpt u)
  ;; the rings and the callout are one undo group, so a run backed out
  ;; halfway takes one U rather than one per circle; the group is only
  ;; closed if it was opened (STANDARDS section 5)
  (defun *error* (msg)
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (setq undo-open nil)
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nBPCALLOUT error: " msg)))
    (if lzd:report (lzd:report "BPCALLOUT" *bpcallout-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "BPCALLOUT" *bpcallout-version*))
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
                   " a click within " (rtos bp:*snap* 4 0)
                   " snaps to the nearest one."))
    (princ (strcat "\nNo survey points found in the drawing - clicks"
                   " will be ringed where picked and named \"?\".")))

  ;; the rings and the text are one chain: Back at the text placement
  ;; re-opens the picking, where a ringed point clicked again un-rings
  ;; it - which is how BPCALLOUT has always taken a pick back
  (setq picked nil txtpt 'RETRY)
  (while (eq txtpt 'RETRY)
  (while (setq pk ((lambda (v) (if lzd:ask (lzd:ask "\nClick a bad point (a ringed one un-rings it, Enter when done): " v) v))
                    (getpoint
                      "\nClick a bad point (a ringed one un-rings it, Enter when done): ")))
    ;; a click answers in the UCS and the survey points are WORLD
    ;; data, so the click is moved into the world before it is matched
    ;; or ringed.  Untranslated, a UCS off the world origin missed
    ;; every point and ringed the bare UCS numbers somewhere else,
    ;; saying "ringed where clicked" over a ring nowhere near the click
    (setq pk (trans pk 1 0))
    (setq hit (bp:nearest-point pk cands))
    (if hit
      (setq ctr (car hit) nm (cdr hit))
      (setq ctr (list (car pk) (cadr pk)) nm bp:*unknown*))
    (setq old (bp:ringed-at pk ctr picked hit))
    (if old
      (progn                            ; reselecting a point undoes it
        (if (and (caddr old) (entget (caddr old)))
          (entdel (caddr old)))
        (setq picked (bp:drop-entry (caddr old) picked))
        (princ (strcat "\n  " bp:*pt-prefix* (cadr old)
                       " un-ringed.")))
      (progn
        (cal:ensure-layer bp:*layer* bp:*layer-color*)
        (setq picked (cons (list ctr nm (bp:draw-ring ctr)) picked))
        (if hit
          (princ (strcat "\n  " bp:*pt-prefix* nm " ringed."))
          (princ (strcat "\n  No survey point within "
                         (rtos bp:*snap* 4 0)
                         " of the pick - ringed where clicked, as "
                         bp:*pt-prefix* bp:*unknown* "."))))))

  (if (null picked)
    (progn
      (princ "\nBPCALLOUT: nothing picked - nothing drawn.")
      (setq txtpt nil))
    (progn
      (setq picked (reverse picked)             ; back to click order
            names  (mapcar 'cadr picked)
            phrase (bp:phrase names)
            lastpt (car (last picked)))
      (initget "Back Undo")
      (setq txtpt (getpoint (strcat "\nPlace the callout text <beside"
                                    " the last ring> [Back]: ")))
      (if lzd:ask (lzd:ask (getvar "LASTPROMPT") txtpt) txtpt)
      (cond
        ((and (= (type txtpt) 'STR) (member txtpt '("Back" "Undo")))
         (princ "\n  Stepping back to the picking.")
         (setq picked (reverse picked)          ; back to newest-first
               txtpt  'RETRY))
        (T
         ;; Enter tucks it right of and below the last ring AS THE
         ;; DRAFTER SEES IT: the step is taken in the UCS and the
         ;; result moved into the world.  Stepped along world X and Y,
         ;; a turned UCS set the callout on a diagonal off the ring,
         ;; reading along the UCS but sitting somewhere else
         (if (null txtpt)
           (setq u     (trans lastpt 0 1)
                 txtpt (trans (list (+ (car u) bp:*text-gap*)
                                    (- (cadr u) bp:*text-gap*)
                                    0.0)
                              1 0))
           (setq txtpt (trans txtpt 1 0)))      ; a click: UCS to world
         (bp:draw-text txtpt phrase)
         (princ (strcat "\nBPCALLOUT: " (itoa (length picked))
                        " point(s) ringed on layer " bp:*layer*
                        ";  \"" phrase "\"")))))))
  (if undo-open (command "_.UNDO" "_End"))
  (setq undo-open nil)
  (if lzd:end (lzd:end "BPCALLOUT"))
  (princ))

(defun c:BPCALLOUTVER ()
  (princ (strcat "\nBPCALLOUT " *bpcallout-version*))
  (princ))

;;; -------------------- self tests --------------------------------------
;; What LAZDIAG runs on the drafter's machine after this tool fails, and
;; writes into the report: the tool's own helpers on inputs whose answers
;; are KNOWN, so the report says whether the arithmetic was sound where
;; it ran.  (label expression expected) passes when the value is equal
;; to expected (to 1e-6); (label expression) passes when it is not nil,
;; and the value is written down either way.  Nothing here may prompt,
;; draw or (command): it is evaluated from inside *error*.
;; tests/test_selftests.py runs every entry in the VM at both tiers.
(defun bp:selftests ()
  (list
    (list "dist measures flat: an elevation is dropped"
          '(cal:dist '(0 0 0) '(3 4 100))                          5.0)
    (list "nearest-point takes the closer of two within snap"
          '(cadr (bp:nearest-point '(0 0) '(((10 0) "12") ((3 0) "15"))))  "15")
    (list "nearest-point passes over a point beyond snap"
          '(bp:nearest-point '(0 0) '(((100 0) "12")))            nil)
    (list "ringed-at finds a ring centred on the same spot"
          '(cadr (bp:ringed-at '(0 0) '(5 5) '(((5.0 5.0) "12" nil)) T))  "12")
    (list "ringed-at: a pick that snapped to a point is that point, not a neighbour's ring"
          '(bp:ringed-at '(2 0) '(8 0) '(((0 0) "12" nil)) T)     nil)
    (list "ringed-at: an unsnapped pick inside a ring names that ring"
          '(cadr (bp:ringed-at '(2 0) '(2 0) '(((0 0) "12" nil)) nil))  "12")
    (list "drop-entry removes the ring's entry and keeps the order"
          '(bp:drop-entry 'r2 '(((0 0) "1" r1) ((1 1) "2" r2) ((2 2) "3" r3)))
          '(((0 0) "1" r1) ((2 2) "3" r3)))
    (list "phrase: one point is bad"
          '(bp:phrase '("12"))                                    "Pt.12 is bad")
    (list "phrase: two points are bad, joined by and"
          '(bp:phrase '("12" "15"))                               "Pt.12 and Pt.15 are bad")
    (list "phrase: three points, commas then and"
          '(bp:phrase '("12" "15" "20"))                          "Pt.12, Pt.15 and Pt.20 are bad")
    (list "the ring radius knob is a positive distance"
          '(if (and (numberp bp:*radius*) (> bp:*radius* 0)) bp:*radius*))))

(foreach c '("BPCALLOUT")
  (setq *calofin-selftests*
        (cons (cons c 'bp:selftests) *calofin-selftests*)))

;; Quiet inside the whole build: LAZPASS.lsp and
;; CALOFIN-LOADER.lsp set the flag while they load their members,
;; because one file's greeting is a greeting and sixty-three of
;; them is a wall the drafter scrolls past in every drawing they
;; open.  APPLOADed alone the flag is nil and this prints, which
;; is the one time somebody wants to be told.  CALVER reports the
;; whole roster whenever it is asked.
(if (not *calofin-quiet*)
  (princ (strcat "\nBPCALLOUT " *bpcallout-version*
                 " loaded. Command: BPCALLOUT (ring bad points and write"
                 " the callout).")))
(princ)
