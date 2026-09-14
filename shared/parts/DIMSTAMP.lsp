;;; ======================================================================
;;; DIMSTAMP.lsp  --  click a point, stamp a feet/inch dimension text
;;;                    there, and repeat
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  DIMSTAMP       stamp dimension text, click after click
;;;            DIMSTAMPVER    print the loaded version
;;;
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;
;;; Click a point and type the text once; it lands there as a TEXT
;;; entity.  Beside it, a little vertical RULER appears -- a column of
;;; nearby values, each drawn as a tick and a label, graded like a real
;;; ruler: the near eighth-inch steps are the smallest text and the
;;; shortest ticks, quarters and halves step up from there, and the
;;; whole-inch jumps (1", 2", 3" either way) are the tallest and
;;; boldest, exactly where the deepest mark on a tape measure would be.
;;; A small CIRCLE rides the row that is the CURRENT value.
;;;
;;; From there, one prompt does three jobs:
;;;   * click empty space           -- stamps the CURRENT text there,
;;;                                    and the ruler follows the click;
;;;   * click a row on the ruler    -- adopts THAT row's value as the
;;;                                    new current text (nothing is
;;;                                    stamped yet; the ruler redraws
;;;                                    in place, re-graded around it);
;;;   * type something else         -- becomes the new current text,
;;;                                    the same way, once it parses.
;;; Enter ends the run.  The ruler is scratch, not drawing content: it
;;; is erased and redrawn every time the current value changes, and
;;; swept away for good when the command ends or is cancelled -- only
;;; the TEXT it actually stamped is left behind.
;;;
;;; Every value is one of four forms, exactly -- nothing else parses:
;;;   34"                     whole inches
;;;   3'-4"                   feet and whole inches
;;;   34 1/2"                 inches and a fraction
;;;   3'- 4 1/2"              feet, inches and a fraction
;;;
;;; What the ruler offers depends on which family the current text is
;;; in:
;;;   * bare inches, no feet (34" or 34 1/2") -- every eighth of an
;;;     inch from there up to the next whole inch (34-1/8" ... 35");
;;;   * feet and inches, fraction or not (3'-4" or 3'- 4 1/2") -- every
;;;     eighth of an inch up and down for up to 7/8" either side, THEN
;;;     whole-inch jumps of 1", 2" and 3" beyond that on each side --
;;;     quarters and eighths together on the one ruler, told apart by
;;;     tier rather than by switching which the tool offers.
;;; A row that would come out at or below zero is dropped.
;;;
;;; Versioning: see tools/release_lisp.py at the repo root.  It reads
;;; *dimstamp-version* below and stamps a dated, REV-numbered twin of
;;; this file into releases/.
;;; ======================================================================

;;; -------------------- version ---------------------------------------
(setq *dimstamp-version* "v2.0")   ; announced on load; release_lisp.py
                                   ; reads this banner and stamps the
                                   ; dated twin in releases/ from it

;;; -------------------- tunables --------------------------------------
(setq ds:*layer* "DIMENSION")       ; layer the stamped text (and the
                                    ; scratch ruler) lands on -- the
                                    ; same layer name ABFIND, CDCREATE
                                    ; and CDCALLOUT use for their own
                                    ; dimension text
(setq ds:*layer-color* 7)          ; ACI colour the layer is CREATED
                                    ; with -- 7 is AutoCAD's own
                                    ; black-on-white/white-on-black
                                    ; swap, so it reads on any screen
                                    ; without a measured 'auto knob.  A
                                    ; layer already in the drawing
                                    ; keeps its own colour
(setq ds:*text-hgt* 6.0)           ; TEXT height of a stamped value,
                                    ; and of the ruler's own biggest
                                    ; (jump-tier) row labels
(setq ds:*ruler-gap* 24.0)         ; how far right of the anchor point
                                    ; the ruler's spine sits
(setq ds:*ruler-row-gap* 9.0)      ; vertical distance between one
                                    ; ruler row and the next
(setq ds:*ruler-ticklen* 4.0)      ; tick length for the tallest
                                    ; (current/jump) rows; smaller
                                    ; tiers scale it down
(setq ds:*ruler-txt-gap* 2.0)      ; gap between a tick's outer end
                                    ; and where its label starts
(setq ds:*ruler-circle-r* 1.5)     ; radius of the circle marking the
                                    ; current value's row
(setq ds:*ruler-click-width* 70.0) ; how far right of the spine a
                                    ; click still counts as picking a
                                    ; row rather than an empty-space
                                    ; stamp -- generous, since a label
                                    ; is never measured for its real
                                    ; width
(setq ds:*ruler-hit-pad* 2.0)      ; how far LEFT of the spine still
                                    ; counts too, so a click that lands
                                    ; just shy of it is not read as
                                    ; empty space

;;; -------------------- helpers ----------------------------------------

;; T when every character of S is 0-9 and S is not empty.
(defun ds:digit-p (c)
  (and (>= (ascii c) 48) (<= (ascii c) 57)))

(defun ds:digits-p (s / i n ok)
  (setq n (strlen s) ok (> n 0) i 1)
  (while (and ok (<= i n))
    (if (not (ds:digit-p (substr s i 1))) (setq ok nil))
    (setq i (1+ i)))
  ok)

;; Parse a measurement string into (EIGHTHS HASFEET), where EIGHTHS is
;; the total value in eighths of an inch (an integer) and HASFEET is T
;; when the text used feet notation -- carried back through so a value
;; renders, and is offered further suggestions, in the family it came
;; in.  nil when S is not one of the four canonical forms in the
;; header.
(defun ds:parse (s / n apos feetstr rest hasfeet feetnum spc wholestr
                    fracstr slash numstr denstr wholenum num den frac
                    ok eighths)
  (setq ok T)
  (setq s (vl-string-trim " \t" s))
  (setq n (strlen s))
  (if (or (= n 0) (/= (substr s n 1) "\""))
    (setq ok nil)
    (setq s (substr s 1 (1- n))))
  (setq hasfeet nil feetnum 0)
  (if (and ok (setq apos (vl-string-search "'" s)))
    (progn
      (setq feetstr (substr s 1 apos))
      (setq rest (substr s (+ apos 2)))
      (if (or (= feetstr "") (not (ds:digits-p feetstr)))
        (setq ok nil)
        (setq feetnum (atoi feetstr) hasfeet T))
      (setq rest (vl-string-trim " " rest))
      (if (and ok (> (strlen rest) 0) (= (substr rest 1 1) "-"))
        (setq rest (vl-string-trim " " (substr rest 2)))
        (setq ok nil)))
    (setq rest (vl-string-trim " " s)))
  (setq wholenum 0 frac 0.0)
  (if ok
    (progn
      (setq spc (vl-string-search " " rest))
      (if spc
        (setq wholestr (substr rest 1 spc)
              fracstr  (vl-string-trim " " (substr rest (+ spc 2))))
        (setq wholestr rest fracstr nil))
      (if (or (= wholestr "") (not (ds:digits-p wholestr)))
        (setq ok nil)
        (setq wholenum (atoi wholestr)))
      (if (and ok fracstr)
        (progn
          (setq slash (vl-string-search "/" fracstr))
          (if (null slash)
            (setq ok nil)
            (progn
              (setq numstr (substr fracstr 1 slash)
                    denstr (substr fracstr (+ slash 2)))
              (if (or (not (ds:digits-p numstr)) (not (ds:digits-p denstr))
                      (= (atoi denstr) 0))
                (setq ok nil)
                (setq num (atoi numstr) den (atoi denstr)
                      frac (/ (float num) (float den))))))))))
  (if ok
    (progn
      (setq eighths (fix (+ 0.5 (* 8.0 (+ (* feetnum 12.0) wholenum frac)))))
      (list eighths hasfeet))
    nil))

;; Render TOTAL-EIGHTHS (an integer count of 1/8" units) back to text,
;; in the HASFEET family the source text used -- feet notation, or
;; plain inches regardless of magnitude.  The fraction is simplified
;; and shown only when the remainder is not a whole inch.
(defun ds:format (total-eighths hasfeet / feet remeighths whole f8 g num den)
  (if hasfeet
    (setq feet (/ total-eighths 96)
          remeighths (- total-eighths (* feet 96)))
    (setq feet 0 remeighths total-eighths))
  (setq whole (/ remeighths 8)
        f8    (- remeighths (* whole 8))
        num   0
        den   1)
  (if (/= f8 0)
    (progn
      (setq g (gcd f8 8))
      (setq num (/ f8 g) den (/ 8 g))))
  (cond
    ((and hasfeet (/= num 0))
     (strcat (itoa feet) "'- " (itoa whole) " " (itoa num) "/" (itoa den)
             "\""))
    ((and hasfeet (= num 0))
     (strcat (itoa feet) "'-" (itoa whole) "\""))
    ((/= num 0)
     (strcat (itoa whole) " " (itoa num) "/" (itoa den) "\""))
    (T
     (strcat (itoa whole) "\""))))

;; The RULER TIER an offset of OFFSET eighths from the current value
;; falls in -- 'jump for a whole inch or more, 'half/'quarter/'eighth
;; for the finer steps, biggest to smallest.  This is what a row's
;; tick length and text height read off; ds:suggestions tags every row
;; with it as the row is generated.
(defun ds:tier (offset / a m)
  (setq a (abs offset) m (rem a 8))
  (cond
    ((= m 0) 'jump)
    ((= m 4) 'half)
    ((member m '(2 6)) 'quarter)
    (T 'eighth)))

;; The nearby values to offer, as a list of (EIGHTHS TIER) pairs (see
;; the header banner for what each family offers); a row that would
;; come out at or below zero is dropped.  Unsorted -- the ruler sorts
;; once it also has the current row to place among them.
(defun ds:suggestions (total-eighths hasfeet / out i off)
  (setq out nil)
  (if (not hasfeet)
    (progn
      ;; bare inches: every eighth from here up to the next whole inch
      (setq i 1)
      (while (<= i 8)
        (setq out (cons (list (+ total-eighths i) (ds:tier i)) out))
        (setq i (1+ i))))
    (progn
      ;; feet involved: eighths up and down for up to 7/8" a side...
      (setq i 1)
      (while (<= i 7)
        (setq out (cons (list (- total-eighths i) (ds:tier i)) out))
        (setq out (cons (list (+ total-eighths i) (ds:tier i)) out))
        (setq i (1+ i)))
      ;; ...then whole-inch jumps of 1, 2 and 3 beyond that, each side
      (setq i 1)
      (while (<= i 3)
        (setq off (* i 8))
        (setq out (cons (list (- total-eighths off) 'jump) out))
        (setq out (cons (list (+ total-eighths off) 'jump) out))
        (setq i (1+ i)))))
  (vl-remove-if '(lambda (pr) (<= (car pr) 0)) out))

;; Ascending by value -- the comparator ds:draw-ruler sorts rows with.
(defun ds:val-lt (a b) (< (car a) (car b)))

;; TEXT height for a ruler row of this TIER.
(defun ds:ruler-hgt (tier)
  (cond
    ((eq tier 'half) (* ds:*text-hgt* 0.8))
    ((eq tier 'quarter) (* ds:*text-hgt* 0.65))
    ((eq tier 'eighth) (* ds:*text-hgt* 0.5))
    (T ds:*text-hgt*)))            ; 'current and 'jump

;; Tick length for a ruler row of this TIER.
(defun ds:ruler-tick (tier)
  (cond
    ((eq tier 'half) (* ds:*ruler-ticklen* 0.75))
    ((eq tier 'quarter) (* ds:*ruler-ticklen* 0.55))
    ((eq tier 'eighth) (* ds:*ruler-ticklen* 0.35))
    (T ds:*ruler-ticklen*)))       ; 'current and 'jump

;; Write STR at PT.
(defun ds:draw-text (pt str)
  (entmakex (list '(0 . "TEXT") '(100 . "AcDbEntity")
                  (cons 8 ds:*layer*) '(100 . "AcDbText")
                  (cons 10 (list (car pt) (cadr pt) 0.0))
                  (cons 40 ds:*text-hgt*)
                  (cons 1 str))))

;; Erase every entity in ENTS -- how the scratch ruler is swept away,
;; before a redraw and for good when the run ends.
(defun ds:erase-ents (ents / e)
  (foreach e ents (if (and e (entget e)) (entdel e))))

;; Draw the ruler beside AP for the current value (TOTAL-EIGHTHS,
;; HASFEET), one row per suggestion plus a circled CURRENT row among
;; them.  Returns (ENTS SPX ROWS): the entities drawn (for
;; ds:erase-ents), the ruler's spine X (for a click's X test), and
;; ROWS as a list of (VALUE ROW-Y) pairs (for a click's Y test).
(defun ds:draw-ruler (ap total-eighths hasfeet / rows n i row val tier y
                          hgt tl spx ents lbl ty result)
  (cal:ensure-layer ds:*layer* ds:*layer-color*)
  (setq rows (cons (list total-eighths 'current)
                   (ds:suggestions total-eighths hasfeet)))
  (setq rows (vl-sort rows 'ds:val-lt))
  (setq n (length rows) i 0 ents nil result nil
        spx (+ (car ap) ds:*ruler-gap*))
  (foreach row rows
    (setq val (car row) tier (cadr row))
    (setq y (+ (cadr ap) (* i ds:*ruler-row-gap*)))
    (setq hgt (ds:ruler-hgt tier))
    (setq tl  (ds:ruler-tick tier))
    (setq ents (cons
                (entmakex (list '(0 . "LINE") '(100 . "AcDbEntity")
                                (cons 8 ds:*layer*) '(100 . "AcDbLine")
                                (cons 10 (list spx y 0.0))
                                (cons 11 (list (+ spx tl) y 0.0))))
                ents))
    (setq lbl (ds:format val hasfeet))
    (setq ty (- y (/ hgt 2.0)))
    (setq ents (cons
                (entmakex (list '(0 . "TEXT") '(100 . "AcDbEntity")
                                (cons 8 ds:*layer*) '(100 . "AcDbText")
                                (cons 10 (list (+ spx tl ds:*ruler-txt-gap*)
                                              ty 0.0))
                                (cons 40 hgt)
                                (cons 1 lbl)))
                ents))
    (if (eq tier 'current)
      (setq ents (cons
                  (entmakex (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                                  (cons 8 ds:*layer*) '(100 . "AcDbCircle")
                                  (cons 10 (list spx y 0.0))
                                  (cons 40 ds:*ruler-circle-r*)))
                  ents)))
    (setq result (cons (list val y) result))
    (setq i (1+ i)))
  (setq ents (cons
              (entmakex (list '(0 . "LINE") '(100 . "AcDbEntity")
                              (cons 8 ds:*layer*) '(100 . "AcDbLine")
                              (cons 10 (list spx (cadr ap) 0.0))
                              (cons 11 (list spx
                                             (+ (cadr ap)
                                                (* (1- n) ds:*ruler-row-gap*))
                                             0.0))))
              ents))
  (list ents spx (reverse result)))

;; Erase OLDENTS and draw a fresh ruler at AP for PARSED -- the
;; (EIGHTHS HASFEET) pair ds:parse hands back.
(defun ds:redraw-ruler (ap parsed oldents)
  (ds:erase-ents oldents)
  (ds:draw-ruler ap (car parsed) (cadr parsed)))

;; The ruler row (if any) that PT lands on, close enough in Y to one
;; of ROWS and within the ruler's column in X -- nil when PT is empty
;; space, meant as a stamp point instead.  Returns the row's VALUE.
(defun ds:ruler-hit (pt spx rows / r best bd d)
  (setq best nil bd nil)
  (if (and spx (>= (car pt) (- spx ds:*ruler-hit-pad*))
                (<= (car pt) (+ spx ds:*ruler-click-width*)))
    (foreach r rows
      (setq d (abs (- (cadr pt) (cadr r))))
      (if (and (<= d (/ ds:*ruler-row-gap* 2.0)) (or (null bd) (< d bd)))
        (setq best (car r) bd d))))
  best)

;; One validated free-text answer.  PROMPT already carries its leading
;; \n and trailing ": ".  Loops on anything that is not one of the
;; four canonical forms.
(defun ds:ask-raw (prompt / v)
  (setq v (getstring T prompt))
  (if lzd:ask (lzd:ask prompt v) v)
  (if (ds:parse v)
    v
    (progn
      (princ (strcat "\nDIMSTAMP: \"" v "\" is not one of the four forms"
                     " (34\", 3'-4\", 34 1/2\", 3'- 4 1/2\") - try again."))
      (ds:ask-raw prompt))))

;; The very first text of a run: no default, no ruler yet -- nothing
;; exists to build one around.
(defun ds:ask-first ()
  (ds:ask-raw "\nText, e.g. 34\", 3'-4\", 34 1/2\" or 3'- 4 1/2\": "))

;; The second-and-later prompt: one click or one typed line does every
;; job.  Returns nil for Enter (done), (adopt TEXT) for a new current
;; value picked off the ruler or typed fresh, or (stamp PT) for a
;; point to stamp the CURRENT text at.  SPX and ROWS are the live
;; ruler's hit-test data from ds:draw-ruler/ds:redraw-ruler; HASFEET is
;; the current value's family, for formatting a ruler pick.
(defun ds:next-action (spx rows hasfeet / pk hitval)
  (initget 128)
  (setq pk (getpoint (strcat "\nClick to place text, click the ruler to"
                             " change it, or type new text (Enter when"
                             " done): ")))
  (if lzd:ask (lzd:ask "ds:next-action" pk) pk)
  (cond
    ((null pk) nil)
    ((= (type pk) 'STR)
     (if (ds:parse pk)
       (list 'adopt pk)
       (progn
         (princ (strcat "\nDIMSTAMP: \"" pk "\" is not one of the four"
                        " forms (34\", 3'-4\", 34 1/2\", 3'- 4 1/2\") -"
                        " try again."))
         (ds:next-action spx rows hasfeet))))
    (T
     (setq hitval (ds:ruler-hit pk spx rows))
     (if hitval
       (list 'adopt (ds:format hitval hasfeet))
       (list 'stamp pk)))))

;;; -------------------- the command ------------------------------------
;; NOTE: no local here may be named after a function this routine
;; calls - an AutoLISP local SHADOWS the function of the same name for
;; the whole call, so a local called "last" turns every (last ...) in
;; the body into "no function definition: LAST" at runtime.
(defun c:DIMSTAMP (/ *error* undo-open pk lasttext count parsed anchor
                    rulerents rulerx rulerrows action rr)
  (defun *error* (msg)
    (ds:erase-ents rulerents)
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (setq undo-open nil)
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nDIMSTAMP error: " msg)))
    (if lzd:report (lzd:report "DIMSTAMP" *dimstamp-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "DIMSTAMP" *dimstamp-version*))
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn
      (command "_.UNDO" "_Begin")
      (setq undo-open T)))

  (princ (strcat "\nDIMSTAMP " *dimstamp-version*
                 " - click a point, then give the text.  After that,"
                 " click to stamp again, click the ruler to change the"
                 " value, or type a new one; Enter when done."))
  (setq count 0 rulerents nil)
  (setq pk (getpoint "\nClick a point to place text (Enter when done): "))
  (if pk
    (progn
      (setq lasttext (ds:ask-first))
      (cal:ensure-layer ds:*layer* ds:*layer-color*)
      (ds:draw-text pk lasttext)
      (setq count 1 anchor pk parsed (ds:parse lasttext))
      (princ (strcat "\n  \"" lasttext "\" placed."))
      (setq rr (ds:redraw-ruler anchor parsed rulerents)
            rulerents (car rr) rulerx (cadr rr) rulerrows (caddr rr))
      (while (setq action (ds:next-action rulerx rulerrows (cadr parsed)))
        (cond
          ((= (car action) 'stamp)
           (cal:ensure-layer ds:*layer* ds:*layer-color*)
           (ds:draw-text (cadr action) lasttext)
           (setq count (1+ count) anchor (cadr action))
           (princ (strcat "\n  \"" lasttext "\" placed.")))
          (T                                    ; 'adopt
           (setq lasttext (cadr action) parsed (ds:parse lasttext))))
        (setq rr (ds:redraw-ruler anchor parsed rulerents)
              rulerents (car rr) rulerx (cadr rr) rulerrows (caddr rr)))
      (ds:erase-ents rulerents)
      (setq rulerents nil)))

  (princ (strcat "\nDIMSTAMP: " (itoa count) " placed."))
  (if undo-open (command "_.UNDO" "_End"))
  (setq undo-open nil)
  (if lzd:end (lzd:end "DIMSTAMP"))
  (princ))

(defun c:DIMSTAMPVER ()
  (princ (strcat "\nDIMSTAMP " *dimstamp-version*))
  (princ))

;; Quiet inside the whole build: LAZPASS.lsp and CALOFIN-LOADER.lsp set
;; the flag while they load their members.  APPLOADed alone the flag
;; is nil and this prints, which is the one time somebody wants to be
;; told.  CALVER reports the whole roster whenever it is asked.
(if (not *calofin-quiet*)
  (princ (strcat "\nDIMSTAMP " *dimstamp-version*
                 " loaded. Command: DIMSTAMP (stamp dimension text,"
                 " click after click).")))
(princ)
