;;; ======================================================================
;;; DIMSTAMP.lsp  --  click a point, stamp a feet/inch dimension text
;;;                    or a letter label there, and repeat
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
;;; upright in the current UCS.  The layer, the style, the height and
;;; the wrap are knobs in the block below; the attachment, the ByLayer
;;; colour and the turn are not -- they are how the shop's text is.
;;;
;;; Beside it, a little vertical RULER appears -- a column of nearby
;;; values, each drawn as a tick and a label, graded like a real ruler:
;;; the near eighth-inch steps are the smallest text and the shortest
;;; ticks, quarters and halves step up from there, and the whole-inch
;;; jumps (1", 2", 3" either way) are the tallest and boldest, exactly
;;; where the deepest mark on a tape measure would be.
;;;
;;; The CURRENT row is not one of the options -- it is where you
;;; already are -- so it is drawn as a stamp rather than as a ruler:
;;; tick, label and a RING round the spine all go on the stamp's own
;;; layer at the stamp's own colour, while every row you can pick
;;; stays the ruler's.  That is what makes the row you are on read
;;; differently from the rows you can click, and read as the thing it
;;; would stamp.
;;;
;;; The ruler is pinned to the SCREEN, not to the drawing: it is drawn
;;; down a strip near the RIGHT edge of whatever the current view is
;;; showing and sized as a fraction of that view, so it stays the same
;;; size and in the same place whether the drawing is zoomed to a whole
;;; pool or to one step.  It re-pins every time it redraws.  The right
;;; edge is where it sits over the least drawing: a pool is drawn from
;;; the middle out and dimensioned along its sides, and the ruler is
;;; scratch -- it should be the thing at the edge of the eye, not the
;;; thing a stamp has to be placed around.
;;;
;;; Its rows reach INWARD from that spine, and that is not a knob: a
;;; tick and a label hung off the outside of a spine pinned near an
;;; edge would be drawn past the edge, where nothing can be read and a
;;; pick is a pan away.  So the side decides the direction --
;;; ds:*ruler-screen-x* past the middle of the view reaches left, short
;;; of it reaches right -- and the ruler is inside the view wherever it
;;; is pinned.  That strip is reserved: a click inside it picks a row,
;;; so stamps land outside it.
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
;;; The stack carries its own HEIGHT and ALIGNMENT codes, and they are
;;; what the shop's own dimension text carries: an MTEXT out of one of
;;; these drawings reads \A1;33'-2{\H1x;\S1/2;}", not a bare stack.
;;; Both matter, and for the same reason -- left alone, AutoCAD draws
;;; a stack SMALLER than the text it sits in (70% of it, the
;;; TSTACKSIZE default), so the half in 34 1/2" came out a size down
;;; from the 34 it belongs to, and a stack sized back up has to sit on
;;; the line rather than tower over it.  So ds:*stack-hgt* is 1.0, the
;;; size of the number beside it, and ds:*stack-align* is 1, centred.
;;; The braces close the height change at the end of the stack, so the
;;; inch mark after it is back at the stamp's own height rather than
;;; inheriting the fraction's.
;;;
;;;   the plain spelling  reads as           drawn (MTEXT)
;;;   ------------------  -----------------  --------------------------
;;;   34"                 34"                34"
;;;   3'-4"               3'-4"              3'-4"
;;;   34 1/2"             34 over-a-half "   \A1;34{\H1.0000x;\S1/2;}"
;;;   4'-1 1/2"           4'-1 over-a-half " \A1;4'-1{\H1.0000x;\S1/2;}"
;;;
;;; The plain spelling on the left is what a prompt offers, what the
;;; command line echoes and what ds:parse reads back -- nothing stacks
;;; on a command line, and 4'-11/2" there would read as eleven halves.
;;; The drawn one reaches an MTEXT and nothing else; ds:drawn is the
;;; one door between them, so no call site can forget it.
;;;
;;; LETTERS are the other thing it stamps, and the reason is that the
;;; survey points are named in them: type a letter rather than a
;;; measurement and the whole tool turns over to labelling.  A is 1, Z
;;; is 26, AA is 27 -- a spreadsheet's columns, which is the sequence
;;; a shop whose points arrive in Excel already reads -- and the ruler
;;; offers the letters either side instead of the eighths of an inch,
;;; because what is near A is B, not 1/8".
;;;
;;; The one real difference is what a stamp leaves behind.  A
;;; measurement STAYS: dimensioning is stamping 34" in three places,
;;; so the next click stamps it again.  A letter MOVES ON: a run of
;;; labels is A, B, C and never A, A, A, so the value steps by one as
;;; it lands and the next click stamps the next letter.  That is what
;;; makes a lot of them worth stamping -- click, click, click -- and
;;; ds:*letter-advance* turns it off for the drawing that wants the
;;; same label twice.  The line back says which letter is next, so a
;;; run can be read off the command line without looking at the ruler.
;;;
;;; A label is one or two letters (ds:*letter-max*), which is A
;;; through ZZ, 702 of them.  More than that is a word typed by
;;; mistake, and being told so beats finding NOPE stamped on a sheet.
;;; Nothing in a label stacks, so its drawn spelling and its plain one
;;; are the same string.
;;;
;;; What it READS is far looser, because nobody types a dimension
;;; carefully twice.  The inch mark is optional and may be two
;;; apostrophes, the dash after the feet mark is optional, inches may
;;; be decimal, and a fraction may be spaced or dashed -- so
;;;
;;;   4'4.5    4'-4 1/2"    4' 4-1/2    4'4 1/2    52.5    52 1/2
;;;
;;; all read, and the first four all mean 4'-4 1/2".  Anything not a
;;; whole eighth is rounded to the nearest one.
;;;
;;; A SPACE is only read at the FIRST text prompt, which takes a whole
;;; line.  The click-or-type prompt after it is a getpoint, and there
;;; the spacebar is Enter: 4'-6 1/2" typed at it arrives as two
;;; answers, 4'-6 and then 1/2", and the second used to be adopted on
;;; its own -- the next click stamped half an inch where 4'-6 1/2" was
;;; meant, and only two "read as" lines said so.  So the prompts teach
;;; the dashed spelling, 4'-4-1/2", which is one answer anywhere; and a
;;; typed answer that can only be the tail of the one typed just
;;; before it, with no click between -- a bare fraction after a value
;;; with none, or the inches after a bare 4' -- is read back together
;;; with it and said so, not adopted as a value of its own.  Somebody
;;; who did mean 4'-6 and then half an inch alone types 1/2" once more:
;;; the same answer again is never the tail of the join it just made,
;;; and the line that reports the join says so.
;;;
;;; What is STAMPED is always the canonical spelling above, never the
;;; keystrokes: type 4'4.5 and the line back reads "read as 4'-4 1/2"",
;;; which is where a mis-typed value is caught by eye rather than in
;;; the drawing.  Feet spelled means feet written, so 52.5 stays 52 1/2"
;;; rather than becoming 4'-4 1/2".
;;;
;;; The ruler offers, around whatever the current value is, the four
;;; letters either side when it is a label -- and when it is a
;;; measurement, every eighth of an inch for a WHOLE INCH EITHER SIDE -- 44" offers 43"
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
(setq *dimstamp-version* "v3.9")   ; announced on load; release_lisp.py
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
(setq ds:*stack-hgt* 1.0)          ; how tall that stacked fraction is
                                    ; drawn, as a factor of the text
                                    ; around it.  1.0 is the size of
                                    ; the whole inches beside it, which
                                    ; is how this shop's dimension text
                                    ; reads; AutoCAD left to itself
                                    ; draws a stack at 0.7 (its
                                    ; TSTACKSIZE default), a size down
                                    ; from the number it belongs to.
                                    ; nil writes no height code at all
                                    ; and leaves that default alone
(setq ds:*stack-align* 1)          ; where that fraction sits against
                                    ; the line it is on: 0 bottom, 1
                                    ; centred, 2 top, and 1 is what the
                                    ; shop's own dimension text carries
                                    ; (\A1;33'-2{\H1x;\S1/2;}" out of
                                    ; one of these drawings).  It is
                                    ; the other half of drawing a
                                    ; full-height stack: sized back up
                                    ; and left to sit on the baseline,
                                    ; a fraction towers over the number
                                    ; it belongs to.  nil writes no
                                    ; alignment code at all

;; -- the ruler.  Scratch geometry, and pinned to the SCREEN: every
;;    size below is a fraction of the current view, so the ruler looks
;;    the same at any zoom.
(setq ds:*ruler-layer* "DIMSTAMP RULER")  ; layer the scratch ruler is
                                    ; drawn on -- its own, so the TEXT
                                    ; layer never carries scratch
(setq ds:*ruler-color* 3)          ; ACI colour of the ruler, on the
                                    ; entities themselves so it reads
                                    ; the same whatever its layer says
(setq ds:*ruler-screen-x* 0.88)    ; where the spine sits across the
                                    ; view: a fraction of the view's
                                    ; WIDTH in from its LEFT edge, so
                                    ; 0.88 is near the right edge --
                                    ; the strip that sits over the
                                    ; least of the drawing.  The rows
                                    ; reach INWARD from the spine
                                    ; whichever side it is on, so a
                                    ; value under 0.5 puts the ruler
                                    ; back on the left and turns the
                                    ; rows round to reach right
(setq ds:*ruler-row-frac* 0.042)   ; one row's share of the view's
                                    ; HEIGHT -- the ruler's whole size
                                    ; knob.  Raise it for a bigger
                                    ; ruler with fewer rows on screen
(setq ds:*ruler-txt-frac* 0.5)     ; the biggest row label's height,
                                    ; as a fraction of the row spacing
(setq ds:*ruler-tick-frac* 0.6)    ; the longest tick, same measure
(setq ds:*ring-frac* 0.26)         ; the ring round the CURRENT row, as
                                    ; a fraction of the row spacing.
                                    ; Bigger than a tick is long on
                                    ; purpose: the row you are on should
                                    ; be the first thing the eye finds
(setq ds:*current-color* nil)      ; ACI colour of that current row --
                                    ; nil is ByLayer, and since the row
                                    ; is drawn on the STAMP's layer that
                                    ; means it reads in exactly the
                                    ; colour the stamp will.  A number
                                    ; here overrides that
(setq ds:*letter-max* 2)           ; how many letters a LABEL may be.
                                    ; 2 covers A through ZZ -- 702
                                    ; labels, more than a drawing has
                                    ; points -- and anything longer is
                                    ; a word, not a label: a slip of
                                    ; the keyboard still gets told it
                                    ; is not a measurement rather than
                                    ; being stamped as one
(setq ds:*letters-either-side* 4)  ; how many letters the ruler offers
                                    ; each way round the current one.
                                    ; A row before A is dropped, the
                                    ; way a measurement at or below
                                    ; zero is
(setq ds:*letter-advance* T)       ; a LETTER stamp moves the current
                                    ; value on to the next letter, so
                                    ; a run of labels is click, click,
                                    ; click for A, B, C -- they are
                                    ; never A, A, A, which is what
                                    ; makes stamping a lot of them
                                    ; worth doing.  nil stamps the
                                    ; same letter until you change it,
                                    ; the way a measurement does
(setq ds:*ruler-reach* 6.0)        ; how far INBOARD of the spine -- the
                                    ; way the rows run -- in row
                                    ; spacings, a click still counts as
                                    ; picking a row rather than as an
                                    ; empty-space stamp.  The far side
                                    ; of the spine is half a row
                                    ; spacing, which is the tick itself

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

;; A LETTER LABEL as its place in the sequence: A is 1, Z is 26, AA
;; is 27, AB 28 -- the way a spreadsheet's columns run, which is the
;; progression a shop whose points arrive in Excel already reads.
;; Case does not matter going in and what comes back out is upper
;; case, so a typed "b" is stamped "B".
;;
;; nil when S is not letters at all, and nil when it is MORE letters
;; than ds:*letter-max*: a label is one or two letters, so a longer
;; run of them is a word somebody typed by mistake, and telling them
;; that beats stamping NOPE on their drawing.
(defun ds:letter-index (s / n i c out)
  (setq s (vl-string-trim " \t" s)
        n (strlen s)
        i 1
        out 0)
  (if (and (> n 0) (<= n ds:*letter-max*))
    (progn
      (while (and out (<= i n))
        (setq c (ascii (strcase (substr s i 1))))
        (if (and (>= c 65) (<= c 90))
          (setq out (+ (* out 26) (- c 64)))
          (setq out nil))
        (setq i (1+ i)))
      out)))

;; The other way round: place N in that sequence, spelled.  1 is "A",
;; 26 "Z", 27 "AA".  NOTE: the remainder is "r", not "rem" -- rem IS
;; an AutoLISP function, and a local of that name shadows it for every
;; call this one makes.
(defun ds:letter-name (n / out r)
  (setq out "")
  (while (> n 0)
    (setq r   (rem (1- n) 26)
          out (strcat (chr (+ 65 r)) out)
          n   (/ (- n 1 r) 26)))
  out)

;; Parse an answer into (VALUE FAMILY) -- the pair every other part of
;; this tool is handed, and the only place that decides which of the
;; two things DIMSTAMP stamps an answer is.
;;
;;   (EIGHTHS nil)      a MEASUREMENT in plain inches, EIGHTHS being
;;                      the total in eighths of an inch, an integer
;;                      rounded to the nearest one
;;   (EIGHTHS T)        the same, with FEET spelled -- carried back
;;                      through so a value renders, and is offered
;;                      further suggestions, in the family it was
;;                      typed in
;;   (INDEX 'letter)    a LETTER LABEL, INDEX being its place in the
;;                      sequence (A is 1).  The survey points are
;;                      named this way, and a drawing wants a run of
;;                      them rather than one
;;
;; The two cannot collide: a measurement never spells letters and a
;; label never spells digits.
;;
;; Deliberately LENIENT, because nobody types a dimension carefully
;; twice: the inch mark is optional and may be two apostrophes, the
;; dash after the feet mark is optional, inches may be decimal, and a
;; fraction may be spaced or dashed.  4'4.5, 4'-4 1/2", 4' 4-1/2 and
;; 52.5 all read; what gets STAMPED is always ds:format's canonical
;; spelling, never what was typed.  nil when the text is not a
;; measurement at all, or reads as nothing at all.
(defun ds:parse (s / n apos feetstr rest hasfeet feet inch eighths raw
                     lidx)
  (setq s   (vl-string-trim " \t" s)
        raw s                          ; kept for the letter attempt:
                                       ; the inch mark and the feet
                                       ; split chew s up below
        n   (strlen s))
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
  ;; an empty inches part is only an answer when feet carried it.
  ;; NOTE: a cond and not an (or ...) -- AutoLISP's or hands back T,
  ;; never the value that made it true, so (or (list ...) ...) answers
  ;; T and every caller's (car p) dies "bad argument type: consp T".
  ;; v3.6 shipped exactly that, and every run failed at its first text.
  (cond
    ((and inch (or hasfeet (/= rest ""))
          (> (setq eighths (fix (+ 0.5 (* 8.0 (+ (* feet 12.0) inch)))))
             0))
     (list eighths hasfeet))
    ;; not a measurement, then a LETTER LABEL -- the other family
    ;; this tool stamps, and the one the survey points are named in
    ((setq lidx (ds:letter-index raw)) (list lidx 'letter))))

;; STR -- a stacked fraction, \S code and all -- wrapped in the height
;; code that draws it at ds:*stack-hgt* times the text around it.  A
;; stack AutoCAD is left to size itself comes out at 70% of that text
;; (TSTACKSIZE), a size down from the whole inches it belongs to, and
;; a dimension reads as one number or it does not read: the fraction
;; is part of the measurement, not a footnote to it.
;;
;; The BRACES are the other half of the job.  \H runs to the end of
;; its enclosing group, so without them the height would carry on past
;; the stack and take the inch mark with it; inside them it ends where
;; the fraction does and the " after it is back at the stamp's own
;; size.  A nil knob writes no code at all, which is the bare \S
;; spelling and AutoCAD's own default height.
(defun ds:stack-sized (str)
  (if ds:*stack-hgt*
    (strcat "{\\H" (rtos ds:*stack-hgt* 2 4) "x;" str "}")
    str))

;; The alignment code a line carrying a stack opens with, or "" when
;; the knob is nil.  It goes at the FRONT of the whole string, ahead of
;; the whole inches, which is where the shop's own dimension text
;; carries it -- \A applies from where it stands, and what is being
;; aligned is the line the stack sits on, not the stack alone.  A line
;; with no fraction in it has nothing to align and gets no code.
(defun ds:stack-aligned ()
  (if ds:*stack-align*
    (strcat "\\A" (itoa ds:*stack-align*) ";")
    ""))

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
;;   T   -- DRAWN: "\A1;34{\H1.0000x;\S1/2;}"", AutoCAD's stacking
;;          code at the height ds:stack-sized gives it, on a line
;;          ds:stack-aligned centres, and NO space in front of it.
;;          The stack IS the separation; a space there only pushes the
;;          inch mark away from the number.  This is the spelling that
;;          reaches an MTEXT, and nothing else.
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
             (T (ds:stack-sized
                  (strcat "\\S" (itoa num) ds:*stack* (itoa den) ";")))))
  (strcat (if (and stacked (/= num 0)) (ds:stack-aligned) "")
          (if hasfeet (strcat (itoa feet) "'-") "")
          (itoa whole) fr "\""))

;; The PLAIN spelling: what a prompt offers, what the command line
;; says, and what ds:parse reads back.
(defun ds:format (value family)
  (if (eq family 'letter)
    (ds:letter-name value)
    (ds:spell value family nil)))

;; The DRAWN spelling: the same value with its fraction stacked, for
;; an MTEXT and nowhere else.  A LETTER has only the one spelling --
;; there is nothing in a label to stack, so the drawn one and the
;; plain one are the same string, and saying so here is what keeps the
;; stack codes out of a stamped A.
(defun ds:stacked (value family)
  (if (eq family 'letter)
    (ds:letter-name value)
    (ds:spell value family T)))

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

;; The nearby values to offer, as a list of (VALUE TIER) pairs (see the
;; header banner for what each family offers); a row that would come
;; out at or below zero -- or before A -- is dropped.  Unsorted -- the
;; ruler sorts once it also has the current row to place among them.
;; One door, and it is the family that picks which side of it.
(defun ds:suggestions (value family)
  (if (eq family 'letter)
    (ds:letter-suggestions value)
    (ds:measure-suggestions value family)))

;; The letters either side of INDEX.  Every row is one whole letter
;; from the last -- there is no eighth of a letter -- so they are all
;; the one tier and all drawn alike, and the only row that reads
;; differently is the CURRENT one, which the ruler already draws as
;; the stamp it would make.
(defun ds:letter-suggestions (index / out i)
  (setq out nil i 1)
  (while (<= i ds:*letters-either-side*)
    (setq out (cons (list (- index i) 'jump) out))
    (setq out (cons (list (+ index i) 'jump) out))
    (setq i (1+ i)))
  (vl-remove-if '(lambda (pr) (<= (car pr) 0)) out))

;; The measurements either side, which is the other half of the door
;; above.
(defun ds:measure-suggestions (total-eighths hasfeet / out i off)
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

;; Which way a ruler row reaches from the spine: 1.0 toward higher x,
;; -1.0 toward lower.  It is derived, not a knob, and it is what lets
;; the ruler sit at either edge: a tick and a label hung off the
;; OUTSIDE of a spine pinned near an edge would be drawn past that
;; edge, off the screen the whole thing is pinned to, so the rows
;; always run toward the middle of the view.  The spine's own side is
;; the only thing that has to be said, and ds:*ruler-screen-x* says it.
(defun ds:ruler-dir ()
  (if (> ds:*ruler-screen-x* 0.5) -1.0 1.0))

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

;; A point in the current UCS as the WORLD point entmake wants.  Every
;; point this tool draws at is a UCS one -- a click answers in the UCS,
;; and the ruler is laid out from VIEWCTR, which is in the UCS too --
;; and entmake reads group 10 as WORLD.  Without this a UCS moved off
;; the world origin put every stamp that far from its click, and the
;; ruler that far off the screen, while the run said "placed".
(defun ds:wcs (x y)
  (trans (list x y 0.0) 1 0))

;; How far the current UCS is turned from the world X axis, so text
;; reads along the UCS the drafter is drawing in.  Taken off the UCS X
;; axis moved into the world -- not off UCSXDIR run back into the UCS,
;; which is (1 0 0) there however far the UCS is turned, so it would
;; always answer zero.  0 in the world UCS.
(defun ds:ucsang ( / v)
  (setq v (trans '(1.0 0.0 0.0) 1 0 T))
  (atan (cadr v) (car v)))

;; One MTEXT, written the way the shop's dimension text is: the tool's
;; own style, unwrapped, upright, attached at PT by ATT -- 1 top left,
;; 3 top right, AutoCAD's own codes.  A stamp is always 1, the way the
;; shop's text is; a ruler label takes 3 when its row reaches LEFT, so
;; the label grows away from the spine instead of over it.  COL is an
;; ACI number for the scratch ruler's own colour, or nil for ByLayer,
;; which is what a real stamp takes.
(defun ds:mtext (pt hgt str lay col att / dxf)
  (setq dxf (list '(0 . "MTEXT") '(100 . "AcDbEntity") (cons 8 lay)))
  (if col (setq dxf (append dxf (list (cons 62 col)))))
  (entmakex
    (append dxf
            (list '(100 . "AcDbMText")
                  (cons 10 (ds:wcs (car pt) (cadr pt)))
                  (cons 40 hgt)
                  (cons 41 ds:*text-width*)   ; 0 = no wrap
                  (cons 71 att)               ; 1 top left, 3 top right
                  '(72 . 5)                   ; direction: by style
                  (cons 1 str)
                  (cons 7 ds:*style*)
                  (cons 50 (ds:ucsang))       ; upright in the UCS
                  '(73 . 1)                   ; line spacing: at least
                  (cons 44 ds:*line-space*)))))

;; Stamp STR at PT -- the drawing content this whole tool exists for.
;; STR arrives in the plain spelling and is drawn in the stacked one.
(defun ds:stamp (pt str)
  (ds:mtext pt ds:*text-hgt* (ds:drawn str) ds:*layer* nil 1))

;; Erase every entity in ENTS -- how the scratch ruler is swept away,
;; before a redraw and for good when the run ends.
(defun ds:erase-ents (ents / e)
  (foreach e ents (if (and e (entget e)) (entdel e))))

;; A ruler stroke from (X1 Y1) to (X2 Y2) on LAY, in COL -- or ByLayer
;; when COL is nil, which is how the current row takes the stamp
;; layer's own colour.
(defun ds:ruler-line (x1 y1 x2 y2 lay col)
  (entmakex (append (list '(0 . "LINE") '(100 . "AcDbEntity")
                          (cons 8 lay))
                    (if col (list (cons 62 col)))
                    (list '(100 . "AcDbLine")
                          (cons 10 (ds:wcs x1 y1))
                          (cons 11 (ds:wcs x2 y2))))))

;; The ring that marks the current row, same layer and colour rule.
(defun ds:ruler-ring (x y r lay col)
  (entmakex (append (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                          (cons 8 lay))
                    (if col (list (cons 62 col)))
                    (list '(100 . "AcDbCircle")
                          (cons 10 (ds:wcs x y))
                          (cons 40 r)))))

;; Draw the ruler down its strip of the CURRENT VIEW for the current
;; value (TOTAL-EIGHTHS, HASFEET), one row per suggestion plus a
;; ringed CURRENT row among them, the whole thing centred vertically
;; in the view.  Returns (ENTS BOX ROWS): the entities drawn (for
;; ds:erase-ents), BOX as (XMIN XMAX YTOL) for a click's hit test, and
;; ROWS as a list of (VALUE ROW-Y) pairs.
;;
;; Every row but one is an OPTION, and they are drawn alike: the
;; ruler's own layer, the ruler's own colour.  The CURRENT row is not
;; an option -- it is where you already are -- so tick, label and ring
;; alike go on the STAMP's layer at the stamp's colour, which is what
;; makes the row you are on read differently from the rows you can
;; pick, and makes it read as what it would stamp.
(defun ds:draw-ruler (total-eighths hasfeet / rows n i row val tier y
                          hgt tl spx ents lbl result view vx vy vw vh
                          gap base rlay rcol dir far near)
  (cal:ensure-layer ds:*ruler-layer* ds:*ruler-color*)
  (cal:ensure-layer ds:*layer* ds:*layer-color*)   ; the current row's
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
        dir  (ds:ruler-dir)           ; rows run inward from the spine
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
    ;; where you ARE is drawn as the stamp; what you can PICK is drawn
    ;; as the ruler
    (if (eq tier 'current)
      (setq rlay ds:*layer*       rcol ds:*current-color*)
      (setq rlay ds:*ruler-layer* rcol ds:*ruler-color*))
    (setq ents (cons (ds:ruler-line spx y (+ spx (* dir tl)) y rlay rcol)
                     ents))
    ;; the ruler is drawn text too, so its rows stack the way a stamp
    ;; off that row will -- the label IS the preview
    (setq lbl (ds:stacked val hasfeet))
    ;; half a label's height above the tick puts it astride its own
    ;; row, and the attachment turns with the row: a label on a row
    ;; that reaches left is hung by its RIGHT edge, so it grows away
    ;; from the spine rather than back across it
    (setq ents (cons (ds:mtext (list (+ spx (* dir (+ tl (* gap 0.35))))
                                     (+ y (/ hgt 2.0)))
                               hgt lbl rlay rcol
                               (if (< dir 0.0) 3 1))
                     ents))
    (if (eq tier 'current)
      (setq ents (cons (ds:ruler-ring spx y (* gap ds:*ring-frac*)
                                      rlay rcol)
                       ents)))
    (setq result (cons (list val y) result))
    (setq i (1+ i)))
  (setq ents (cons (ds:ruler-line spx base spx (+ base (* (- n 1) gap))
                                  ds:*ruler-layer* ds:*ruler-color*)
                   ents))
  ;; the strip a click counts as a pick in: the reach on the side the
  ;; rows run, half a spacing on the other -- the tick's own side
  (setq near (+ spx (* dir gap ds:*ruler-reach*))
        far  (- spx (* dir (/ gap 2.0))))
  (list ents
        (list (min near far) (max near far) (/ gap 2.0))
        (reverse result)))

;; What to carry forward after stamping PARSED.  A run of labels is A,
;; B, C and never A, A, A, so a letter moves on by one as it is
;; stamped and the next click lands the next letter -- which is the
;; whole of "stamp a lot of letters": click, click, click.  A
;; measurement stays put, because stamping the same one in three
;; places is exactly what dimensioning is.
(defun ds:advance (parsed)
  (if (and ds:*letter-advance* (eq (cadr parsed) 'letter))
    (list (1+ (car parsed)) 'letter)
    parsed))

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
  (princ (strcat "\nDIMSTAMP: \"" v "\" is not a measurement or a label"
                 " - try 44, 44.5, 44-1/2, 4'4.5, 4'-4-1/2\", or a"
                 " letter like A or AB.")))

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
  (ds:ask-raw "\nText - 4'-4-1/2\", just 4'4.5, or a letter like A: "))

;; S with its inch mark taken off the end, however it was spelled --
;; a double quote or two apostrophes -- and trimmed.
(defun ds:no-inch-mark (s / n)
  (setq s (vl-string-trim " \t" s)
        n (strlen s))
  (cond
    ((and (>= n 2) (= (substr s (1- n) 2) "''")) (substr s 1 (- n 2)))
    ((and (>= n 1) (= (substr s n 1) "\"")) (substr s 1 (1- n)))
    (T s)))

;; The one answer PREV and NEW were typed as, when NEW can only be the
;; tail the spacebar cut off PREV -- nil when NEW is an answer of its
;; own.  At a getpoint a space is Enter, so 4'-6 1/2" arrives as 4'-6
;; and then 1/2", and 4' 4-1/2 as 4' and then 4-1/2.  PREV is the raw
;; text of a typed answer with no click after it (nil otherwise), and
;; it has to be a measurement left OPEN: no inch mark closing it and
;; no fraction in it yet.  NEW has to be inches with no feet in it,
;; and either a bare fraction under an inch or -- after a PREV that
;; stops at its feet mark -- under a foot.  34 then 36 is somebody
;; changing their mind, and is left to be exactly that.
(defun ds:rejoin (prev new / p nb toks joined q)
  (if prev
    (progn
      (setq p      (vl-string-trim " \t" prev)
            nb     (ds:no-inch-mark new)
            toks   (ds:split nb)
            joined (strcat p " " (vl-string-trim " \t" new)))
      (if (and (= p (ds:no-inch-mark p))
               (not (vl-string-search "/" p))
               (setq q (ds:parse p))
               (not (eq (cadr q) 'letter))
               (not (vl-string-search "'" nb))
               (ds:inches nb)
               (or (and (= 1 (length toks))
                        (vl-string-search "/" (car toks))
                        (< (ds:inches nb) 1.0))
                   (and (= (substr p (strlen p) 1) "'")
                        (< (ds:inches nb) 12.0)))
               (ds:read joined))
        joined))))

;; The second-and-later prompt: one click or one typed line does every
;; job.  Returns nil for Enter (done), (adopt TEXT) for a new current
;; value picked off the ruler, (adopt TEXT TYPED) for one typed fresh
;; -- TYPED being what was typed, for the next prompt's PREV -- or
;; (stamp PT) for a point to stamp the CURRENT text at.  BOX and ROWS
;; are the live ruler's hit-test data from ds:draw-ruler/
;; ds:redraw-ruler; HASFEET is the current value's family, for
;; formatting a ruler pick.  PREV is the text typed at the prompt just
;; before this one when that was a typed answer, for ds:rejoin.
(defun ds:next-action (box rows hasfeet prev / pk hitval canon joined)
  (initget 128)
  (setq pk (getpoint (strcat "\nClick to place text, click the ruler to"
                             " change it, or type new text (Enter when"
                             " done): ")))
  (if lzd:ask (lzd:ask "ds:next-action" pk) pk)
  (cond
    ((null pk) nil)
    ((= (type pk) 'STR)
     (cond
       ;; the tail of the answer before it: read the two together and
       ;; say why, since the drafter typed one value and the spacebar
       ;; made it two.  And say how to get the tail ALONE, for the one
       ;; who did mean 4'-6 and then half an inch by itself: the same
       ;; answer again, which can never be the tail of the join it has
       ;; just made: that join is closed by the fraction or inch mark it
       ;; took, or no longer stops at its feet mark
       ((setq joined (ds:rejoin prev pk))
        (setq canon (ds:read joined))
        (princ (strcat "\n  A space ends the answer at this prompt, so \""
                       (vl-string-trim " \t" prev) "\" and \""
                       (vl-string-trim " \t" pk) "\" came in as two -"
                       " read together as " canon ".  Type "
                       (vl-string-translate " " "-" canon)
                       " to give it in one, or " (vl-string-trim " \t" pk)
                       " again to take it on its own."))
        (list 'adopt canon joined))
       ((setq canon (ds:read pk))
        (if (/= canon (vl-string-trim " \t" pk))
          (princ (strcat "\n  read as " canon)))
        (list 'adopt canon pk))
       (T
        (ds:say-unread pk)
        (ds:next-action box rows hasfeet nil))))
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
                    rulerents rulerbox rulerrows action rr typed)
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
                 " value, or type a new one - dashed, 4'-6-1/2\", since a"
                 " space there is Enter; Enter when done."))
  (setq count 0 rulerents nil)
  (setq pk (getpoint "\nClick a point to place text (Enter when done): "))
  (if lzd:ask (lzd:ask "\nClick a point to place text (Enter when done): " pk) pk)
  (if pk
    (progn
      (setq lasttext (ds:ask-first))
      (cal:ensure-layer ds:*layer* ds:*layer-color*)
      (ds:ensure-style ds:*style*)
      (ds:stamp pk lasttext)
      (setq count 1 parsed (ds:parse lasttext))
      (princ (strcat "\n  \"" lasttext "\" placed."))
      (setq parsed (ds:advance parsed))
      (if (/= lasttext (ds:format (car parsed) (cadr parsed)))
        (progn
          (setq lasttext (ds:format (car parsed) (cadr parsed)))
          (princ (strcat " Next: " lasttext "."))))
      (setq rr (ds:redraw-ruler parsed rulerents)
            rulerents (car rr) rulerbox (cadr rr) rulerrows (caddr rr))
      (setq typed nil)
      (while (setq action (ds:next-action rulerbox rulerrows (cadr parsed)
                                          typed))
        ;; what was typed, when this answer was typed: a click -- a
        ;; stamp or a ruler pick -- ends any answer the spacebar split
        (setq typed (caddr action))
        (cond
          ((= (car action) 'stamp)
           (cal:ensure-layer ds:*layer* ds:*layer-color*)
           (ds:stamp (cadr action) lasttext)
           (setq count (1+ count))
           (princ (strcat "\n  \"" lasttext "\" placed."))
           ;; a letter moves on as it is stamped, so the next click
           ;; lands the next one; a measurement stays where it is
           (setq parsed (ds:advance parsed))
           (if (/= lasttext (ds:format (car parsed) (cadr parsed)))
             (progn
               (setq lasttext (ds:format (car parsed) (cadr parsed)))
               (princ (strcat " Next: " lasttext ".")))))
          (T                                    ; 'adopt
           (setq lasttext (cadr action) parsed (ds:parse lasttext))))
        (setq rr (ds:redraw-ruler parsed rulerents)
              rulerents (car rr) rulerbox (cadr rr) rulerrows (caddr rr)))
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
                 " loaded. Command: DIMSTAMP (stamp dimension text or"
                 " letter labels, click after click).")))
(princ)
