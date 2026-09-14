;;; ======================================================================
;;; DIMSTAMP.lsp  --  click a point, stamp a feet/inch dimension text
;;;                    there, and repeat
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  DIMSTAMP       stamp dimension text, click after click
;;;            DIMSTAMPVER    print the loaded version
;;;
;;; What it stamps is an MTEXT written the way this shop's dimension
;;; text already is: the TEXT layer, the Attributes style, 6" high,
;;; attached TOP LEFT at the point clicked, unwrapped, ByLayer colour,
;;; no rotation.  Every one of those is a knob in the block below.
;;;
;;; Beside it, a little vertical RULER appears -- a column of nearby
;;; values, each drawn as a tick and a label, graded like a real ruler:
;;; the near eighth-inch steps are the smallest text and the shortest
;;; ticks, quarters and halves step up from there, and the whole-inch
;;; jumps (1", 2", 3" either way) are the tallest and boldest, exactly
;;; where the deepest mark on a tape measure would be.  A small CIRCLE
;;; rides the row that is the CURRENT value.
;;;
;;; The ruler is pinned to the SCREEN, not to the drawing: it is drawn
;;; down a strip near the left of whatever the current view is showing
;;; and sized as a fraction of that view, so it stays the same size and
;;; in the same place whether the drawing is zoomed to a whole pool or
;;; to one step.  It re-pins every time it redraws.  That strip is
;;; reserved -- a click inside it picks a row, so stamps land outside
;;; it; ds:*ruler-screen-x* moves it if it is ever in the way.
;;;
;;; From there, one prompt does three jobs:
;;;   * click empty space           -- stamps the CURRENT text there;
;;;   * click a row on the ruler    -- adopts THAT row's value as the
;;;                                    new current text (nothing is
;;;                                    stamped yet; the ruler redraws
;;;                                    re-graded around it);
;;;   * type something else         -- becomes the new current text,
;;;                                    the same way, once it parses.
;;; Enter ends the run.  The ruler is scratch, not drawing content: it
;;; lives on its own layer, is erased and redrawn every time the
;;; current value changes, and is swept away for good when the command
;;; ends or is cancelled -- only the MTEXT it actually stamped is left
;;; behind.
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
(setq *dimstamp-version* "v3.0")   ; announced on load; release_lisp.py
                                   ; reads this banner and stamps the
                                   ; dated twin in releases/ from it

;;; -------------------- tunables --------------------------------------

;; -- what a stamp IS.  These are the MTEXT properties the shop's own
;;    dimension text carries; change one and every later stamp takes it.
(setq ds:*layer* "TEXT")            ; layer the stamped MTEXT lands on.
                                    ; Created when the drawing lacks it;
                                    ; thawed, unlocked and switched on
                                    ; when it is there but unusable
(setq ds:*layer-color* 7)          ; ACI colour that layer is CREATED
                                    ; with -- 7 is AutoCAD's own
                                    ; black-on-white/white-on-black
                                    ; swap.  A layer already in the
                                    ; drawing keeps its own colour, and
                                    ; the stamp itself is ByLayer
(setq ds:*style* "Attributes")      ; text style the stamp is written
                                    ; in.  A drawing without it gets a
                                    ; plain variable-height style of
                                    ; that name made, and is told so
(setq ds:*text-hgt* 6.0)           ; MTEXT height of a stamp
(setq ds:*text-width* 0.0)         ; its defined (wrap) width; 0 is no
                                    ; wrap at all, so a value can never
                                    ; break across two lines
(setq ds:*line-space* 1.0)         ; line space factor, at the "at
                                    ; least" spacing style

;; -- the ruler.  Scratch geometry, and pinned to the SCREEN: every
;;    size below is a fraction of the current view, so the ruler looks
;;    the same at any zoom.
(setq ds:*ruler-layer* "DIMSTAMP RULER")  ; layer the scratch ruler is
                                    ; drawn on -- its own, so the TEXT
                                    ; layer never carries scratch
(setq ds:*ruler-color* 3)          ; ACI colour of the ruler, on the
                                    ; entities themselves so it reads
                                    ; the same whatever its layer says
(setq ds:*ruler-screen-x* 0.12)    ; where the spine sits across the
                                    ; view: a fraction of the view's
                                    ; WIDTH in from its left edge.
                                    ; Raise it to move the ruler right,
                                    ; out of the way of work at the
                                    ; left of the screen
(setq ds:*ruler-row-frac* 0.042)   ; one row's share of the view's
                                    ; HEIGHT -- the ruler's whole size
                                    ; knob.  Raise it for a bigger
                                    ; ruler with fewer rows on screen
(setq ds:*ruler-txt-frac* 0.5)     ; the biggest row label's height,
                                    ; as a fraction of the row spacing
(setq ds:*ruler-tick-frac* 0.6)    ; the longest tick, same measure
(setq ds:*ruler-reach* 6.0)        ; how far right of the spine, in row
                                    ; spacings, a click still counts as
                                    ; picking a row rather than as an
                                    ; empty-space stamp

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

;; What the screen is showing, as (LEFT BOTTOM WIDTH HEIGHT) in drawing
;; units.  This is what pins the ruler to the same strip of screen at
;; any zoom: VIEWSIZE is the view's height, and its width is that times
;; the viewport's own aspect, which SCREENSIZE reports in pixels.
(defun ds:view ( / ctr vh ss aspect vw)
  (setq ctr (getvar "VIEWCTR")
        vh  (getvar "VIEWSIZE")
        ss  (getvar "SCREENSIZE"))
  (setq aspect (if (and ss (listp ss) (numberp (car ss))
                        (numberp (cadr ss)) (> (cadr ss) 0))
                 (/ (float (car ss)) (float (cadr ss)))
                 1.6))                    ; no viewport to measure
  (setq vw (* vh aspect))
  (list (- (car ctr) (/ vw 2.0)) (- (cadr ctr) (/ vh 2.0)) vw vh))

;; Label height for a ruler row of this TIER, against a row spacing of
;; GAP.
(defun ds:ruler-hgt (tier gap / base)
  (setq base (* gap ds:*ruler-txt-frac*))
  (cond
    ((eq tier 'half) (* base 0.8))
    ((eq tier 'quarter) (* base 0.65))
    ((eq tier 'eighth) (* base 0.5))
    (T base)))                     ; 'current and 'jump

;; Tick length for a ruler row of this TIER, same measure.
(defun ds:ruler-tick (tier gap / base)
  (setq base (* gap ds:*ruler-tick-frac*))
  (cond
    ((eq tier 'half) (* base 0.75))
    ((eq tier 'quarter) (* base 0.55))
    ((eq tier 'eighth) (* base 0.35))
    (T base)))                     ; 'current and 'jump

;; Create the output layer, or make sure it is on, thawed, unlocked.
(defun ds:ensure-layer (name colour / rec ed flags col fixed)
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
          (princ (strcat "\nDIMSTAMP: layer " name
                         " was off, frozen or locked - restored so the"
                         " result is visible.")))))))

;; The text style the stamps are written in.  A drawing that already
;; has it keeps its own font and settings, untouched; one that does not
;; gets a plain variable-height style of that name, and is told -- an
;; entmake naming a style the drawing has not got is refused outright,
;; so the alternative is a click that silently draws nothing.
(defun ds:ensure-style (name)
  (if (not (tblsearch "STYLE" name))
    (progn
      (entmakex (list '(0 . "STYLE") '(100 . "AcDbSymbolTableRecord")
                      '(100 . "AcDbTextStyleTableRecord")
                      (cons 2 name) '(70 . 0)
                      '(40 . 0.0)            ; variable height: the
                                             ; entity's own governs
                      '(41 . 1.0) '(50 . 0.0) '(71 . 0) '(42 . 2.5)
                      '(3 . "txt") '(4 . "")))
      (princ (strcat "\nDIMSTAMP: text style " name
                     " was not in this drawing - a plain one was made"
                     " so the stamps have a style to carry."))))
  name)

;; One MTEXT, written the way the shop's dimension text is: attached
;; TOP LEFT at PT, the tool's own style, unwrapped, upright.  COL is
;; an ACI number for the scratch ruler's own colour, or nil for
;; ByLayer, which is what a real stamp takes.
(defun ds:mtext (pt hgt str lay col / dxf)
  (setq dxf (list '(0 . "MTEXT") '(100 . "AcDbEntity") (cons 8 lay)))
  (if col (setq dxf (append dxf (list (cons 62 col)))))
  (entmakex
    (append dxf
            (list '(100 . "AcDbMText")
                  (cons 10 (list (car pt) (cadr pt) 0.0))
                  (cons 40 hgt)
                  (cons 41 ds:*text-width*)   ; 0 = no wrap
                  '(71 . 1)                   ; attachment: top left
                  '(72 . 5)                   ; direction: by style
                  (cons 1 str)
                  (cons 7 ds:*style*)
                  '(50 . 0.0)                 ; rotation
                  '(73 . 1)                   ; line spacing: at least
                  (cons 44 ds:*line-space*)))))

;; Stamp STR at PT -- the drawing content this whole tool exists for.
(defun ds:stamp (pt str)
  (ds:mtext pt ds:*text-hgt* str ds:*layer* nil))

;; Erase every entity in ENTS -- how the scratch ruler is swept away,
;; before a redraw and for good when the run ends.
(defun ds:erase-ents (ents / e)
  (foreach e ents (if (and e (entget e)) (entdel e))))

;; Draw the ruler down its strip of the CURRENT VIEW for the current
;; value (TOTAL-EIGHTHS, HASFEET), one row per suggestion plus a
;; circled CURRENT row among them, the whole thing centred vertically
;; in the view.  Returns (ENTS BOX ROWS): the entities drawn (for
;; ds:erase-ents), BOX as (XMIN XMAX YTOL) for a click's hit test, and
;; ROWS as a list of (VALUE ROW-Y) pairs.
(defun ds:draw-ruler (total-eighths hasfeet / rows n i row val tier y
                          hgt tl spx ents lbl result view vx vy vw vh
                          gap base)
  (ds:ensure-layer ds:*ruler-layer* ds:*ruler-color*)
  (ds:ensure-style ds:*style*)
  (setq rows (cons (list total-eighths 'current)
                   (ds:suggestions total-eighths hasfeet)))
  (setq rows (vl-sort rows 'ds:val-lt))
  (setq view (ds:view)
        vx   (car view)  vy (cadr view)
        vw   (caddr view) vh (cadddr view))
  (setq n    (length rows)
        gap  (* vh ds:*ruler-row-frac*)
        spx  (+ vx (* vw ds:*ruler-screen-x*))
        ;; centred on the view's own middle, however many rows there are
        base (- (+ vy (/ vh 2.0)) (* gap (/ (- n 1) 2.0)))
        i    0
        ents nil
        result nil)
  (foreach row rows
    (setq val (car row) tier (cadr row))
    (setq y (+ base (* i gap)))
    (setq hgt (ds:ruler-hgt tier gap))
    (setq tl  (ds:ruler-tick tier gap))
    (setq ents (cons
                (entmakex (list '(0 . "LINE") '(100 . "AcDbEntity")
                                (cons 8 ds:*ruler-layer*)
                                (cons 62 ds:*ruler-color*)
                                '(100 . "AcDbLine")
                                (cons 10 (list spx y 0.0))
                                (cons 11 (list (+ spx tl) y 0.0))))
                ents))
    (setq lbl (ds:format val hasfeet))
    ;; top-left attachment, so half a label's height above the tick
    ;; puts the label astride its own row
    (setq ents (cons (ds:mtext (list (+ spx tl (* gap 0.35))
                                     (+ y (/ hgt 2.0)))
                               hgt lbl ds:*ruler-layer* ds:*ruler-color*)
                     ents))
    (if (eq tier 'current)
      (setq ents (cons
                  (entmakex (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                                  (cons 8 ds:*ruler-layer*)
                                  (cons 62 ds:*ruler-color*)
                                  '(100 . "AcDbCircle")
                                  (cons 10 (list spx y 0.0))
                                  (cons 40 (* gap 0.18))))
                  ents)))
    (setq result (cons (list val y) result))
    (setq i (1+ i)))
  (setq ents (cons
              (entmakex (list '(0 . "LINE") '(100 . "AcDbEntity")
                              (cons 8 ds:*ruler-layer*)
                              (cons 62 ds:*ruler-color*)
                              '(100 . "AcDbLine")
                              (cons 10 (list spx base 0.0))
                              (cons 11 (list spx (+ base (* (- n 1) gap))
                                             0.0))))
              ents))
  (list ents
        (list (- spx (/ gap 2.0)) (+ spx (* gap ds:*ruler-reach*))
              (/ gap 2.0))
        (reverse result)))

;; Erase OLDENTS and draw a fresh ruler for PARSED -- the
;; (EIGHTHS HASFEET) pair ds:parse hands back.
(defun ds:redraw-ruler (parsed oldents)
  (ds:erase-ents oldents)
  (ds:draw-ruler (car parsed) (cadr parsed)))

;; The ruler row (if any) that PT lands on: inside the ruler's strip in
;; X, and close enough in Y to one of ROWS.  nil when PT is empty
;; space, meant as a stamp point instead.  Returns the row's VALUE.
(defun ds:ruler-hit (pt box rows / r best bd d)
  (setq best nil bd nil)
  (if (and box (>= (car pt) (car box)) (<= (car pt) (cadr box)))
    (foreach r rows
      (setq d (abs (- (cadr pt) (cadr r))))
      (if (and (<= d (caddr box)) (or (null bd) (< d bd)))
        (setq best (car r) bd d))))
  best)

;; One validated free-text answer.  PROMPT already carries its leading
;; \n and trailing ": ".  Loops on anything that is not one of the
;; four canonical forms.
(defun ds:ask-raw (prompt / v)
  (setq v (getstring T prompt))
  (if lzd:ask (lzd:ask prompt v))
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
;; point to stamp the CURRENT text at.  BOX and ROWS are the live
;; ruler's hit-test data from ds:draw-ruler/ds:redraw-ruler; HASFEET is
;; the current value's family, for formatting a ruler pick.
(defun ds:next-action (box rows hasfeet / pk hitval)
  (initget 128)
  (setq pk (getpoint (strcat "\nClick to place text, click the ruler to"
                             " change it, or type new text (Enter when"
                             " done): ")))
  (if lzd:ask (lzd:ask "ds:next-action" pk))
  (cond
    ((null pk) nil)
    ((= (type pk) 'STR)
     (if (ds:parse pk)
       (list 'adopt pk)
       (progn
         (princ (strcat "\nDIMSTAMP: \"" pk "\" is not one of the four"
                        " forms (34\", 3'-4\", 34 1/2\", 3'- 4 1/2\") -"
                        " try again."))
         (ds:next-action box rows hasfeet))))
    (T
     (setq hitval (ds:ruler-hit pk box rows))
     (if hitval
       (list 'adopt (ds:format hitval hasfeet))
       (list 'stamp pk)))))

;;; -------------------- the command ------------------------------------
;; NOTE: no local here may be named after a function this routine
;; calls - an AutoLISP local SHADOWS the function of the same name for
;; the whole call, so a local called "last" turns every (last ...) in
;; the body into "no function definition: LAST" at runtime.
(defun c:DIMSTAMP (/ *error* undo-open pk lasttext count parsed
                    rulerents rulerbox rulerrows action rr)
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
      (ds:ensure-layer ds:*layer* ds:*layer-color*)
      (ds:ensure-style ds:*style*)
      (ds:stamp pk lasttext)
      (setq count 1 parsed (ds:parse lasttext))
      (princ (strcat "\n  \"" lasttext "\" placed."))
      (setq rr (ds:redraw-ruler parsed rulerents)
            rulerents (car rr) rulerbox (cadr rr) rulerrows (caddr rr))
      (while (setq action (ds:next-action rulerbox rulerrows (cadr parsed)))
        (cond
          ((= (car action) 'stamp)
           (ds:ensure-layer ds:*layer* ds:*layer-color*)
           (ds:stamp (cadr action) lasttext)
           (setq count (1+ count))
           (princ (strcat "\n  \"" lasttext "\" placed.")))
          (T                                    ; 'adopt
           (setq lasttext (cadr action) parsed (ds:parse lasttext))))
        (setq rr (ds:redraw-ruler parsed rulerents)
              rulerents (car rr) rulerbox (cadr rr) rulerrows (caddr rr)))
      (ds:erase-ents rulerents)
      (setq rulerents nil)))

  (princ (strcat "\nDIMSTAMP: " (itoa count) " placed."))
  (if undo-open (command "_.UNDO" "_End"))
  (setq undo-open nil)
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
