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
;;; What it WRITES is one of four forms, always -- and a fraction in a
;;; drawn one is STACKED, through AutoCAD's \S code, with no space in
;;; front of it: the stack is the separation, and a space there only
;;; pushes the inch mark off the number.
;;;
;;;   drawn (MTEXT)      reads on the sheet as   the plain spelling
;;;   -----------------  ---------------------   -----------------
;;;   34"                34"                     34"
;;;   3'-4"              3'-4"                   3'-4"
;;;   34\S1/2;"          34 over-a-half "        34 1/2"
;;;   4'-1\S1/2;"        4'-1 over-a-half "      4'-1 1/2"
;;;
;;; The plain spelling on the right is what a prompt offers, what the
;;; command line echoes and what ds:parse reads back -- nothing stacks
;;; on a command line, and 4'-11/2" there would read as eleven halves.
;;; The stacked one reaches an MTEXT and nothing else; ds:drawn is the
;;; one door between them, so no call site can forget it.
;;;
;;; What it READS is far looser, because nobody types a dimension
;;; carefully twice.  The inch mark is optional and may be two
;;; apostrophes, the dash after the feet mark is optional, inches may
;;; be decimal, and a fraction may be spaced or dashed -- so
;;;
;;;   4'4.5    4'-4 1/2"    4' 4-1/2    4'4 1/2    52.5    52 1/2
;;;
;;; all read, and the first four all mean 4'-4 1/2".  Anything not a
;;; whole eighth is rounded to the nearest one.  What is STAMPED is
;;; always the canonical spelling above, never the keystrokes: type
;;; 4'4.5 and the line back reads "read as 4'-4 1/2"", which is
;;; where a mis-typed value is caught by eye rather than in the
;;; drawing.  Feet spelled means feet written, so 52.5 stays 52 1/2"
;;; rather than becoming 4'-4 1/2".
;;;
;;; The ruler offers, around whatever the current value is, every
;;; eighth of an inch for a WHOLE INCH EITHER SIDE -- 44" offers 43"
;;; through 45", the inch before as well as the inch after, since a
;;; measurement is read back off the tape as often downward as up.
;;; Quarters and eighths sit on the one ruler, told apart by tier
;;; rather than by switching which the tool offers.  A value with FEET
;;; in it gets whole-inch jumps of 2" and 3" beyond that inch as well,
;;; on each side.  A row that would come out at or below zero is
;;; dropped.
;;;
;;; Versioning: see tools/release_lisp.py at the repo root.  It reads
;;; *dimstamp-version* below and stamps a dated, REV-numbered twin of
;;; this file into releases/.
;;; ======================================================================

;;; -------------------- version ---------------------------------------
(setq *dimstamp-version* "v3.2")   ; announced on load; release_lisp.py
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
(setq ds:*stack* "/")              ; what separates a STACKED fraction's
                                    ; numerator from its denominator in
                                    ; the drawn MTEXT: "/" is the one
                                    ; over the other with a bar between,
                                    ; "#" the diagonal form, "^" the
                                    ; tolerance stack with no bar

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

;; T when C is 0-9.
(defun ds:digit-p (c)
  (and (>= (ascii c) 48) (<= (ascii c) 57)))

;; T when S reads as a plain decimal number: digits, at most one dot,
;; at least one digit, nothing else.
(defun ds:num-p (s / i n c dots digits ok)
  (setq n (strlen s) i 1 dots 0 digits 0 ok T)
  (while (and ok (<= i n))
    (setq c (substr s i 1))
    (cond
      ((ds:digit-p c) (setq digits (1+ digits)))
      ((= c ".") (setq dots (1+ dots)))
      (T (setq ok nil)))
    (setq i (1+ i)))
  (and ok (> digits 0) (< dots 2)))

;; S cut on spaces, tabs and dashes, empty pieces dropped -- the
;; separators a measurement's inches part is written with, so
;; "4 1/2" and "4-1/2" come apart the same way.
(defun ds:split (s / i n c buf out)
  (setq n (strlen s) i 1 buf "" out nil)
  (while (<= i n)
    (setq c (substr s i 1))
    (if (or (= c " ") (= c "\t") (= c "-"))
      (progn
        (if (/= buf "") (setq out (cons buf out)))
        (setq buf ""))
      (setq buf (strcat buf c)))
    (setq i (1+ i)))
  (if (/= buf "") (setq out (cons buf out)))
  (reverse out))

;; One token of an inches part -- a decimal number, or a fraction N/D
;; -- as a number of inches.  nil when it is neither.
(defun ds:token-val (tok / slash n d)
  (if (setq slash (vl-string-search "/" tok))
    (progn
      (setq n (substr tok 1 slash)
            d (substr tok (+ slash 2)))
      (if (and (ds:num-p n) (ds:num-p d) (/= (atof d) 0.0))
        (/ (atof n) (atof d))))
    (if (ds:num-p tok) (atof tok))))

;; The inches part of a measurement as a number of inches: every token
;; added up, so "4", "4.5", "4 1/2", "4-1/2" and "1/2" all read.  An
;; empty part is 0, which is how 4' reads as 4'-0".  nil when any
;; token is neither a number nor a fraction.
(defun ds:inches (s / toks total v tk)
  (setq toks (ds:split s) total 0.0)
  (foreach tk toks
    (if (and total (setq v (ds:token-val tk)))
      (setq total (+ total v))
      (setq total nil)))
  total)

;; Parse a measurement into (EIGHTHS HASFEET), where EIGHTHS is the
;; total in eighths of an inch (an integer, rounded to the nearest
;; eighth) and HASFEET is T when feet were spelled -- carried back
;; through so a value renders, and is offered further suggestions, in
;; the family it was typed in.
;;
;; Deliberately LENIENT, because nobody types a dimension carefully
;; twice: the inch mark is optional and may be two apostrophes, the
;; dash after the feet mark is optional, inches may be decimal, and a
;; fraction may be spaced or dashed.  4'4.5, 4'-4 1/2", 4' 4-1/2 and
;; 52.5 all read; what gets STAMPED is always ds:format's canonical
;; spelling, never what was typed.  nil when the text is not a
;; measurement at all, or reads as nothing at all.
(defun ds:parse (s / n apos feetstr rest hasfeet feet inch eighths)
  (setq s (vl-string-trim " \t" s)
        n (strlen s))
  ;; the inch mark, however it was spelled, or left off entirely
  (cond
    ((and (>= n 2) (= (substr s (1- n) 2) "''"))
     (setq s (substr s 1 (- n 2))))
    ((and (>= n 1) (= (substr s n 1) "\""))
     (setq s (substr s 1 (1- n)))))
  (setq s (vl-string-trim " \t" s) hasfeet nil feet 0.0)
  (if (setq apos (vl-string-search "'" s))
    (progn
      (setq feetstr (vl-string-trim " \t" (substr s 1 apos))
            rest    (vl-string-trim " \t-" (substr s (+ apos 2))))
      (if (ds:num-p feetstr)
        (setq feet (atof feetstr) hasfeet T)
        (setq rest nil)))                  ; feet that are not a number
    (setq rest (vl-string-trim " \t" s)))
  (setq inch (if rest (ds:inches rest)))
  ;; an empty inches part is only an answer when feet carried it
  (if (and inch (or hasfeet (/= rest "")))
    (progn
      (setq eighths (fix (+ 0.5 (* 8.0 (+ (* feet 12.0) inch)))))
      (if (> eighths 0) (list eighths hasfeet)))))

;; Spell TOTAL-EIGHTHS (an integer count of 1/8" units) out as text,
;; in the HASFEET family the source text used -- feet notation, or
;; plain inches regardless of magnitude.  The fraction is simplified
;; and shown only when the remainder is not a whole inch.
;;
;; STACKED picks which of the two spellings comes out, and they differ
;; in exactly one thing: how the fraction is written.
;;   nil -- PLAIN: " 1/2", spaced off the inches.  Nothing stacks on a
;;          command line, and 4'-11/2" there would read as eleven
;;          halves, so the space earns its keep.  This is the spelling
;;          ds:parse reads back, and the only one ever compared,
;;          prompted with, or printed.
;;   T   -- DRAWN: "\S1/2;", AutoCAD's stacking code, and NO space in
;;          front of it.  The stack IS the separation; a space there
;;          only pushes the inch mark away from the number.  This is
;;          the spelling that reaches an MTEXT, and nothing else.
;; NOTE: the leftover eighths are "remain", not "rem" -- rem IS an
;; AutoLISP function, and a local of that name shadows it for every
;; call this one makes.
(defun ds:spell (total-eighths hasfeet stacked / feet remain whole f8 g
                     num den fr)
  (if hasfeet
    (setq feet   (/ total-eighths 96)
          remain (- total-eighths (* feet 96)))
    (setq feet 0 remain total-eighths))
  (setq whole (/ remain 8)
        f8    (- remain (* whole 8))
        num   0
        den   1)
  (if (/= f8 0)
    (progn
      (setq g (gcd f8 8))
      (setq num (/ f8 g) den (/ 8 g))))
  (setq fr (cond
             ((= num 0) "")
             ((null stacked) (strcat " " (itoa num) "/" (itoa den)))
             (T (strcat "\\S" (itoa num) ds:*stack* (itoa den) ";"))))
  (strcat (if hasfeet (strcat (itoa feet) "'-") "")
          (itoa whole) fr "\""))

;; The PLAIN spelling: what a prompt offers, what the command line
;; says, and what ds:parse reads back.
(defun ds:format (total-eighths hasfeet)
  (ds:spell total-eighths hasfeet nil))

;; The DRAWN spelling: the same value with its fraction stacked, for
;; an MTEXT and nowhere else.
(defun ds:stacked (total-eighths hasfeet)
  (ds:spell total-eighths hasfeet T))

;; STR -- a plain canonical spelling -- as the string that DRAWS it.
;; Every stamp goes through here, so a stacked fraction is not
;; something a call site can forget.  Text that does not parse is
;; drawn as it stands rather than dropped.
(defun ds:drawn (str / p)
  (if (setq p (ds:parse str))
    (ds:stacked (car p) (cadr p))
    str))

;; What S MEANS, in the plain canonical spelling -- the round trip
;; through ds:parse and ds:format that turns 4'4.5 into 4'-4 1/2".
;; nil when S is not a measurement.  Every typed answer goes through
;; this, so nothing but a canonical spelling is ever remembered.
(defun ds:read (s / p)
  (if (setq p (ds:parse s)) (ds:format (car p) (cadr p))))

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
  ;; every eighth of an inch for a WHOLE INCH either side, whatever
  ;; family the value is in: 44" offers 43" through 45", the inch
  ;; before as well as the inch after, because a measurement is read
  ;; back off the tape as often downward as up
  (setq i 1)
  (while (<= i 8)
    (setq out (cons (list (- total-eighths i) (ds:tier i)) out))
    (setq out (cons (list (+ total-eighths i) (ds:tier i)) out))
    (setq i (1+ i)))
  ;; feet as well?  then the 2" and 3" jumps beyond that inch, each
  ;; side -- the 1" jump is already the end of the sweep above
  (if hasfeet
    (progn
      (setq i 2)
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
;; STR arrives in the plain spelling and is drawn in the stacked one.
(defun ds:stamp (pt str)
  (ds:mtext pt ds:*text-hgt* (ds:drawn str) ds:*layer* nil))

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
  (cal:ensure-layer ds:*ruler-layer* ds:*ruler-color*)
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
    ;; the ruler is drawn text too, so its rows stack the way a stamp
    ;; off that row will -- the label IS the preview
    (setq lbl (ds:stacked val hasfeet))
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

;; What to say when something typed is not a measurement at all.  The
;; examples are the lazy spellings on purpose: the ones worth showing
;; are the ones that save keystrokes.
(defun ds:say-unread (v)
  (princ (strcat "\nDIMSTAMP: \"" v "\" is not a measurement - try 44,"
                 " 44.5, 44 1/2, 4'4.5 or 4'-4 1/2\".")))

;; One free-text answer, read as loosely as ds:parse reads and handed
;; back in the CANONICAL spelling.  PROMPT already carries its leading
;; \n and trailing ": ".  A lazy answer is echoed as what it was taken
;; to mean, so a wrong guess is caught by eye and not by the drawing.
(defun ds:ask-raw (prompt / v canon)
  (setq v (getstring T prompt))
  (if lzd:ask (lzd:ask prompt v) v)
  (if (setq canon (ds:read v))
    (progn
      (if (/= canon (vl-string-trim " \t" v))
        (princ (strcat "\n  read as " canon)))
      canon)
    (progn
      (ds:say-unread v)
      (ds:ask-raw prompt))))

;; The very first text of a run: no default, no ruler yet -- nothing
;; exists to build one around.
(defun ds:ask-first ()
  (ds:ask-raw "\nText - 4'-4 1/2\", or just 4'4.5: "))

;; The second-and-later prompt: one click or one typed line does every
;; job.  Returns nil for Enter (done), (adopt TEXT) for a new current
;; value picked off the ruler or typed fresh, or (stamp PT) for a
;; point to stamp the CURRENT text at.  BOX and ROWS are the live
;; ruler's hit-test data from ds:draw-ruler/ds:redraw-ruler; HASFEET is
;; the current value's family, for formatting a ruler pick.
(defun ds:next-action (box rows hasfeet / pk hitval canon)
  (initget 128)
  (setq pk (getpoint (strcat "\nClick to place text, click the ruler to"
                             " change it, or type new text (Enter when"
                             " done): ")))
  (if lzd:ask (lzd:ask "ds:next-action" pk) pk)
  (cond
    ((null pk) nil)
    ((= (type pk) 'STR)
     (if (setq canon (ds:read pk))
       (progn
         (if (/= canon (vl-string-trim " \t" pk))
           (princ (strcat "\n  read as " canon)))
         (list 'adopt canon))
       (progn
         (ds:say-unread pk)
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
      (cal:ensure-layer ds:*layer* ds:*layer-color*)
      (ds:ensure-style ds:*style*)
      (ds:stamp pk lasttext)
      (setq count 1 parsed (ds:parse lasttext))
      (princ (strcat "\n  \"" lasttext "\" placed."))
      (setq rr (ds:redraw-ruler parsed rulerents)
            rulerents (car rr) rulerbox (cadr rr) rulerrows (caddr rr))
      (while (setq action (ds:next-action rulerbox rulerrows (cadr parsed)))
        (cond
          ((= (car action) 'stamp)
           (cal:ensure-layer ds:*layer* ds:*layer-color*)
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
