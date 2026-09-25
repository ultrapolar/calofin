;;; ======================================================================
;;; POOLSIDE.lsp  --  the pool side view (longitudinal section) on its own
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  POOLSIDE     draw the side view from the floor dimensions
;;;            POOLSIDEVER  print the loaded version
;;; ======================================================================
;;;
;;;  A fork of POOL.LSP's side profile, cut loose from the plan.
;;;
;;;  POOL draws that section as a by-product: the shape, the perimeter,
;;;  the corner treatments and -- out of square -- the cross dims are
;;;  all answered before it ever asks a depth, and for a Normal hopper
;;;  no section appears at all.  When the side view IS the job (a
;;;  section to hang under someone else's plan, a depth study, a floor
;;;  chain being checked against the order sheet) POOLSIDE asks for the
;;;  floor dimensions alone and draws it.
;;;
;;;  The letters are POOL's, unchanged, so a field sheet transcribes
;;;  straight across:
;;;
;;;      B    overall length, wall to wall     C    wall height
;;;      D    deep end depth                   C2   depth at the break
;;;
;;;  and the run chain, left to right, which always adds up to B:
;;;
;;;      Normal / SHallow   H  G  F  E     hopper: slope, pad, slope, flat
;;;      SLope              H  F  E        no pad -- a deep line at H
;;;      Wedge              H  F           deep line at H, floor to the wall
;;;      MOdflat            H  G  F        one pad, no shallow flat
;;;      Sport              E2 F2 G F1 E1  symmetric, a flat at each end
;;;
;;;      C  --.___                    ___.--  C           <- waterline
;;;           |   \__            ____/    |
;;;           |      \__________/         |
;;;      |-H--|---G---|----F----|----E----|
;;;
;;;  Any run may be answered NA and is read back off B; when every one
;;;  is given but they still miss B, the pad (G -- or F where the style
;;;  has no pad) absorbs the difference.  A run that resolves negative
;;;  is floored, its dimension drawn RED and a note written under the
;;;  section: the numbers come off a field sheet, and a field sheet can
;;;  disagree with itself.
;;;
;;;  A gray nominal section is on screen while the questions are asked,
;;;  with the tie being asked for lit up RED, so the letters mean
;;;  something before the pool exists.  It deletes itself once the
;;;  answers are in.
;;;
;;;  Output layers are POOL's own -- POOL (section), DIMENSION (dims),
;;;  POOL-NOTES (notes) -- so a POOLSIDE section drops under a POOL
;;;  plan without a layer to reconcile.
;;;
;;;  A FORM CAN ANSWER ALL OF IT.  LAZSIDE fills a section in and hands
;;;  the answers over in psd:*form*; every question below looks there
;;;  first, so a filled-in sheet leaves nothing at the command line but
;;;  the base point.  See "form answers" below for the three states and
;;;  why an answer is REMOVED as it is read.
;;;
;;;  A self-contained file: it carries its own helpers.
;;; ======================================================================

(setq *poolside-version* "v1.16")

;;; -------------------- adjustable constants ---------------------------

(setq psd:*base*       (list 0.0 0.0))  ; insertion base for this run
(setq psd:*sysold*     nil)             ; the user's sysvars, pending restore
(setq psd:*pvents*     nil)             ; live guide entities
(setq psd:*valnotes*   nil)             ; validation problems, for the notes
(setq psd:*pv-col*     'auto)           ; guide outline color: 'auto picks
                                        ; it for the background (grey either
                                        ; way round), a number is used as given
(setq psd:*pvx-col*    7)               ; guide measuring-tie color (white)
(setq psd:*hi-col*     1)               ; highlight color (red)

;; NO dim style is switched anywhere in this file, and that is the
;; rule rather than an omission: every dimension POOLSIDE draws is a
;; FLOOR dim -- the run chain, the depths and B -- and floor dims stay
;; in the drawing's standard style however short they measure, exactly
;; as POOL does since REV23, so the two agree on a 19" H.  (POOL still
;; sets small PLAN dims -- corner radii, cut faces -- in
;; "STANDARD INCHES"; POOLSIDE draws no plan.)

;; The six bottom types, POOL's own keywords and capitalization -- the
;; palette and the field sheets both speak these, and a tool that spelt
;; them differently would be a second vocabulary for one question.
(setq psd:*btypes*  "Normal Sport Wedge SLope MOdflat SHallow")
(setq psd:*btshown* "Normal/Sport/Wedge/SLope/MOdflat/SHallow")

;; Which of the six bottoms the bottom-type question offers on Enter.
;; A shop that draws Sport all day sets it here and stops typing the
;; word; every other bottom is still one keyword away.  Any case will
;; do -- a word psd:*btypes* does not list is not one the prompt would
;; take either, so "Normal" stands.
(setq psd:*btype-default* "Normal")

;; Which end the mirror question offers on Enter: "No" leaves the deep
;; end on the LEFT, the way the letters are measured, and "Yes" offers
;; the section swapped end for end instead, for a shop whose sheets
;; read the other way round.  Either case; anything else leaves "No".
(setq psd:*mirror-default* "No")

;; The LENGTH RULER beside the DEPTH prompts.  A pool's depths are a
;; short list: a wall is built to a handful of heights, a deep end to a
;; handful of depths, and the break between them lands in the span of
;; the two.  So C, D and C2 stand beside DIMSTAMP's ruler, drawn down a
;; strip near the right edge of the view, and a click on a row IS the
;; depth.  The RUNS along the floor are not on it -- those are taped off
;; the sheet, and there is no short list of what a run comes to.
;; Scratch on its own layer, taken down before any prompt that does not
;; take it and on every way out.  Every size is a fraction of the
;; current view, so the ruler reads the same at any zoom.
(setq psd:*ruler-layer* "POOLSIDE-RULER") ; scratch layer the rows go on
(setq psd:*ruler-color* 3)         ; ACI colour of the rows you can PICK
(setq psd:*ruler-current-color* 7) ; ACI colour of the ringed CURRENT
                                   ; row; 7 is AutoCAD's black/white
                                   ; swap
(setq psd:*ruler-screen-x* 0.88)   ; where the spine sits across the
                                   ; view, as a fraction of its width in
                                   ; from the left; past 0.5 the rows
                                   ; reach left, short of it they reach
                                   ; right, so the ruler is always
                                   ; inside the view
(setq psd:*ruler-row-frac* 0.042)  ; one row's share of the view's
                                   ; height -- the ruler's size knob
(setq psd:*ruler-txt-frac* 0.5)    ; the biggest row label's height, as
                                   ; a fraction of the row spacing
(setq psd:*ruler-tick-frac* 0.6)   ; the longest tick, same measure
(setq psd:*ruler-ring-frac* 0.26)  ; the ring round the current row, as
                                   ; a fraction of the row spacing
(setq psd:*ruler-reach* 6.0)       ; how far inboard of the spine, in
                                   ; row spacings, a click still counts
                                   ; as picking a row rather than as the
                                   ; first point of a measured length

;; The three LADDERS those prompts stand on, as (LOW HIGH STEP) in
;; inches -- POOL's own, since the two tools draw the same pool and a
;; depth offered one way here and another there would be two
;; vocabularies for one question.  nil on any of them leaves that
;; prompt the plain typed one it was.
(setq psd:*wallheight-ladder* '(36.0 54.0 3.0))   ; C, the shallow depth
(setq psd:*deepdepth-ladder*  '(60.0 96.0 6.0))   ; D, the deep end
(setq psd:*breakdepth-ladder* '(36.0 96.0 6.0))   ; C2, between the two

;;; -------------------- run state (not tunables) -----------------------
;;;
;;;  The length ruler standing beside a depth prompt.  Declared here
;;;  because AutoLISP wants a global declared at top level, but set and
;;;  cleared by the run itself -- editing it here changes nothing.  A
;;;  module global rather than a local of the sequence, because the
;;;  reader is several calls down from c:POOLSIDE and what that
;;;  command's *error* can take down is what the command can see: Esc
;;;  at a depth is the likeliest way out of the question, and a ruler
;;;  left standing is scratch in somebody's drawing.
(setq psd:*ruler* nil)
;;  T while c:POOLSIDE's own undo group is open.  A global for the same
;;  reason, and reset at the top of every run -- see psd:undobegin.
(setq psd:*undo-open* nil)

;;; -------------------- small vector helpers ---------------------------
;;; Copies of the CALOFIN-LIB originals (STANDARDS.md section 4); the
;;; grouped twin calls cal: instead.

;; A per-ROLE colour override: CalofinInk-<ROLE> in the profile, or nil
;; when none is set -- or when what is set is not a colour (1-255), as an
;; older CALSET could store.  CALOFIN-LIB.lsp's cal:inkoverride is this
;; function; the copy is here because a standalone file has to load alone.
(defun psd:inkoverride (role / q v)
  (setq q (assoc role '((fade . "FADE") (guide . "GUIDE") (dim . "DIM")
                         (hi . "HI") (flag . "FLAG") (arc . "ARC")
                         (olap . "OLAP") (orig . "ORIG") (sugg . "SUGG")
                         (point . "POINT") (constr . "CONSTR")
                         (report . "REPORT"))))
  (if q
    (progn
      (setq v (getenv (strcat "CalofinInk-" (cdr q))))
      (if (and v (/= v "")) (setq v (atoi v)))
      (if (and (numberp v) (< 0 v 256)) v))))

;;  A colour knob set to 'auto asks for the ACI that suits the
;;  background it will be seen against; a knob set to a NUMBER is used
;;  exactly as given, so a shop that has picked its own colours keeps
;;  them and so does a test that sets one.
;;
;;    role     what it is                    dark  light  unmeasured
;;    fade     a review tool's grey-out       251    254        8
;;    guide    preview and guide geometry     253      8        8
;;    dim      a chart tile's dimensions      253      8        8
;;    hi       a chart tile's active box        4      5        5
;;
;;  fade and guide are drawn into the DRAWING, so they measure its
;;  background; dim and hi are drawn inside a dialog, where -15 and -16
;;  already follow AutoCAD's interface theme, so they follow that
;;  instead.  The two are different questions: a light-themed AutoCAD
;;  over the stock near-black model space is an ordinary way to work.
;;  CalofinTheme in the profile overrides both -- CALSET writes it --
;;  and the unmeasured column is what this tool drew before the table
;;  existed, so a session that cannot tell is not a session that
;;  behaves differently.
;;
;;  Nothing is cached: the call sites that run in a loop resolve once
;;  into a local before the loop, which is where the volume is.
;;  CALOFIN-LIB.lsp's cal:ink is this function; the copy is here
;;  because a standalone file has to load alone.
(defun psd:ink (knob role / v th c lum)
  ;; numberp, not (eq knob 'auto): a knob is a colour NUMBER used
  ;; exactly as given, or it is resolved.  Testing for 'auto instead
  ;; would hand back whatever a mistyped knob holds -- nil, or the
  ;; symbol AUOT -- and that reaches entmake as a DXF group 62, where
  ;; it dies a long way from the line that caused it.
  (cond
    ((numberp knob) knob)
    ;; a CalofinInk-<ROLE> override in the profile (CALSET, LAZBACKUP)
    ;; beats the table, as it does in cal:ink -- without this clause the
    ;; grouped build honoured one and this file, loaded alone, did not
    ((psd:inkoverride role))
    (t
      ;; trimmed: this is typed by a person, and " dark " meaning
      ;; nothing at all would be a silent no-op to stare at
      (setq v  (getenv "CalofinTheme")
            v  (if (and v (/= v "")) (strcase (vl-string-trim " \t" v))
                   "AUTO")
            th (cond
                 ((= v "DARK") 'dark)
                 ((= v "LIGHT") 'light)
                 ((member role '(dim hi))
                  (cond ((null (setq c (getvar "COLORTHEME"))) nil)
                        ((= c 0) 'dark)
                        (t 'light)))
                 (t
                  (setq c (vl-catch-all-apply
                            '(lambda ()
                               (vl-load-com)
                               (vla-get-GraphicsWinModelBackgrndColor
                                 (vla-get-Display
                                   (vla-get-Preferences
                                     (vlax-get-acad-object)))))
                            nil))
                  (if (or (vl-catch-all-error-p c) (not (numberp c)))
                    nil
                    (progn
                      ;; an OLE colour is packed low byte first: R, G, B
                      (setq c   (fix c)
                            lum (+ (* 0.30 (rem c 256))
                                   (* 0.59 (rem (/ c 256) 256))
                                   (* 0.11 (rem (/ c 65536) 256))))
                      (if (< lum 128.0) 'dark 'light))))))
      (cond
        ((eq role 'fade)
         (cond ((eq th 'dark) 251) ((eq th 'light) 254) (t 8)))
        ((eq role 'guide)
         (cond ((eq th 'dark) 253) ((eq th 'light) 8) (t 8)))
        ((eq role 'dim)
         (cond ((eq th 'dark) 253) ((eq th 'light) 8) (t 8)))
        ((eq role 'hi)
         (cond ((eq th 'dark) 4) ((eq th 'light) 5) (t 5)))
        (t 7)))))

(defun psd:2d (p) (list (car p) (cadr p)))
(defun psd:v+ (a b) (mapcar '+ (psd:2d a) (psd:2d b)))
(defun psd:v* (v s) (list (* (car v) s) (* (cadr v) s)))
(defun psd:mid (a b) (psd:v* (psd:v+ a b) 0.5))

;; local 2D point -> a point in the CURRENT UCS (applies the insertion
;; base, which was picked there).  This is what (command ...) reads --
;; the _H and _V dimensions and the ZOOMs take their points from it.
(defun psd:wp (p)
  (list (+ (car p) (car psd:*base*))
        (+ (cadr p) (cadr psd:*base*))
        0.0))

;; The same point in WORLD numbers, which is what entmake reads.  Both
;; used to be handed psd:wp: under a UCS moved to the site the section
;; landed at the raw numbers, a UCS-origin away from its own depth and
;; run dimensions, and turned it lay along World X while _H and _V
;; measured along the UCS.  Entity data goes through this one.
(defun psd:ww (p) (trans (psd:wp p) 1 0))

;; How far the current UCS is turned from World X, for a TEXT's 50 so
;; the labels read level in the UCS the section is drawn along.  Read
;; off the components, 0 in World, and kept in 0..2pi.
(defun psd:ucsang ( / x a)
  (setq x (trans '(1.0 0.0 0.0) 1 0 T)
        a (atan (cadr x) (car x)))
  (if (< a 0.0) (+ a pi pi) a))

;; T in a PLAN UCS: one whose Z axis is World +Z, so all it does is
;; move the World plan and turn it -- the only kind the two helpers
;; above can carry a section into.  A TEXT is written face up about a
;; 210 that stays World +Z here: in a UCS whose Z points DOWN (X turned
;; 180, or a 3-point UCS whose Y was picked clockwise of X) every label
;; read backwards beside a section and dims that landed true, and in a
;; tilted one the labels lay flat in the World plan, off the plane the
;; section and its dims are drawn on.  So POOLSIDE refuses both rather
;; than draw either.  The test is on +Z itself and not on its size:
;; (abs z) would let the upside-down one by.
(defun psd:ucsplan-p ()
  (> (caddr (trans '(0.0 0.0 1.0) 1 0 T)) (- 1.0 1.0e-8)))

;; What a refused run says.
(defun psd:ucsrefuse ()
  (princ (strcat "\nPOOLSIDE: the current UCS is tilted or upside down"
                 " (its Z axis is not World +Z),"))
  (princ "\nso a section cannot be laid out in it.  Set the UCS to World, or to")
  (princ "\nany UCS only moved and turned in plan, and run POOLSIDE again.")
  (princ))

;;; -------------------- layers and entities ----------------------------

;; Create the output layer, or - when it already exists - make sure it
;; is on, thawed and unlocked.  Without this a successful run onto a
;; frozen or switched-off layer looks like the command did nothing.
(defun psd:ensure-layer (name color / rec ed flags col fixed)
  (if (not (tblsearch "LAYER" name))
    (entmakex (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                    '(100 . "AcDbLayerTableRecord")
                    (cons 2 name) '(70 . 0) (cons 62 color)
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
          (princ (strcat "\nLayer " name
                         " was off, frozen or locked - restored so the"
                         " result is visible."))))))
  name)

(defun psd:line (p1 p2 lay)
  (entmake (list '(0 . "LINE")
                 (cons 8 lay)
                 (cons 10 (psd:ww p1))
                 (cons 11 (psd:ww p2)))))

(defun psd:text (pt h str lay)
  (entmake (list '(0 . "TEXT")
                 (cons 8 lay)
                 (cons 10 (psd:ww pt))
                 (cons 40 h)
                 (cons 50 (psd:ucsang))      ; level in the UCS
                 (cons 1 str))))

(defun psd:textc (pt h str lay col)
  (entmake (list '(0 . "TEXT")
                 (cons 8 lay)
                 (cons 62 col)
                 (cons 10 (psd:ww pt))
                 (cons 40 h)
                 (cons 50 (psd:ucsang))
                 (cons 1 str))))

;; Override (or set) the color of an entity, refresh it, return it.
(defun psd:setcol (e col / ed old)
  (if (and e (setq ed (entget e)))
      (progn
        (setq old (assoc 62 ed))
        (if old
            (setq ed (subst (cons 62 col) old ed))
            (setq ed (append ed (list (cons 62 col)))))
        (entmod ed)
        (entupd e)))
  e)

;; Read an entity's current color (defaults to the outline gray).
(defun psd:getcol (e / ed)
  (if (and e (setq ed (entget e)) (assoc 62 ed))
      (cdr (assoc 62 ed))
      (psd:ink psd:*pv-col* 'guide)))

;;; -------------------- guide preview ----------------------------------
;;; Everything the guide draws is tracked here, so the *error* handler
;;; can clear it after a cancel mid-prompt.

(defun psd:pvadd (e)
  (setq psd:*pvents* (cons e psd:*pvents*))
  e)

(defun psd:pvkill ( / e)
  (foreach e psd:*pvents* (if (and e (entget e)) (entdel e)))
  (setq psd:*pvents* nil))

;; Guide outline (gray) and guide measuring tie (white, so it reads
;; over the outline).
(defun psd:pvline (p1 p2 ink)
  (psd:line p1 p2 "POOL-NOTES")
  (psd:setcol (entlast) ink))

(defun psd:pvtieline (p1 p2)
  (psd:line p1 p2 "POOL-NOTES")
  (psd:setcol (entlast) psd:*pvx-col*))

;; One lettered guide tie: the measuring line and its letter, both
;; tracked and both lit while that question is being asked.  Returns
;; the highlight entry (letter ent ent).
(defun psd:tie (p q lbl th / e et)
  (setq e (psd:pvadd (psd:pvtieline p q)))
  (psd:text (psd:v+ (psd:mid p q) (list (* 0.5 th) (* 0.5 th)))
            (* 1.2 th) lbl "POOL-NOTES")
  (setq et (psd:pvadd (psd:setcol (entlast) psd:*pvx-col*)))
  (cons lbl (list e et)))

;;; -------------------- user input -------------------------------------
;;; The ask layer of STANDARDS.md section 4, under this file's prefix.

;; The user's own object snaps stay LIVE during every measurement
;; prompt; OSMODE is zeroed only while the routine feeds points to
;; commands, where a snap would grab the wrong geometry.
(defun psd:osup ( / p)
  (setq p (assoc "OSMODE" psd:*sysold*))
  (if p (setvar "OSMODE" (cdr p))))

(defun psd:osdown () (setvar "OSMODE" 0))

;;; -------------------- the length ruler --------------------------------
;;;  DIMSTAMP's ruler, as a helper any LENGTH prompt can stand beside.
;;;  Once a first length has been given, the prompt draws the eighths
;;;  of an inch for a whole inch either side of the last one down a
;;;  strip near the right edge of the view, graded like a tape with the
;;;  last length ringed in the middle -- and one prompt then takes a
;;;  click on a row (that row's value), a typed measurement in any
;;;  spelling (44, 44.5, 44-1/2, 4'4.5, 4'-4-1/2"), Enter, a keyword,
;;;  or a click on empty space as the first of two points to measure
;;;  between, which is what getdist always offered.  A run of
;;;  near-equal lengths is clicked rather than typed over and over.
;;;  The fractions are DASHED because the prompt is a getpoint, where
;;;  the spacebar is Enter: 44 1/2 is two answers there, 44 to this
;;;  question and 1/2 to the next, so a bare fraction is refused
;;;  rather than taken as a length of its own.
;;;
;;;  PERPPTS, CPERPPTS, PERPMARK, CORNERSTP, HEMISTEP and NORMIESTEP
;;;  ask their lengths through it.  Each carries this block under its
;;;  own prefix so the standalone file loads alone, the grouped build
;;;  swaps the copy for the library's, and tests/test_ruler_copies.py
;;;  holds every copy to this one text.  DIMSTAMP keeps its own ruler:
;;;  its current row is drawn as the stamp it would make, on the
;;;  stamp's layer in the stamp's style, which is a different thing
;;;  from a row of nearby lengths.
;;;
;;;  A ruler comes in two families, and the prompt picks which.
;;;
;;;  The TAPE is the one above: the eighths of an inch for a whole inch
;;;  either side of the LAST answer, which is what a run of near-equal
;;;  numbers wants.  It needs a last answer to be built round, so the
;;;  first prompt of a run stands alone.
;;;
;;;  The LADDER is the other: a fixed (LO HI STEP) of the values that
;;;  prompt is actually answered with, every one of them offered from
;;;  the first prompt on.  A corner radius is 3" to 2'-0" by 3" and a
;;;  tape of eighths round nothing helps nobody -- 3, 6, 9, 12 is the
;;;  whole vocabulary, and a drafter picks out of it rather than types
;;;  into it.  Its rows are graded off the VALUE, not off a distance
;;;  from the current row: the foot marks are the deep ones and the
;;;  half-foot next, which is where a tape's deep marks are too.  A
;;;  ladder still takes a typed measurement that is not on it, and the
;;;  answer is then ringed among the rungs as the current row.
;;;
;;;  Nothing in here reads a knob.  A tool hands its knobs in as one
;;;  STYLE list and keeps the ruler between prompts as one STATE list:
;;;    STYLE  (COLOR CURRENT-COLOR SCREEN-X ROW-FRAC TXT-FRAC TICK-FRAC
;;;            RING-FRAC REACH) -- a caller's tunables block says what
;;;            each one moves
;;;    STATE  (LEN FEET ENTS BOX ROWS LAY STYLE SAID LADDER) -- the
;;;            length the ruler stands round (nil = none), the family it
;;;            is labelled in (T = feet), what is drawn, its layer, the
;;;            style, whether the one-line hint has been said, and the
;;;            ladder it is standing on (nil = a tape)
;;;  Values are INCHES, the unit this shop draws in, and the ruler
;;;  steps in eighths of one, which is what a tape reads in.

;; T when C is 0-9.
(defun psd:len-digit-p (c)
  (and (>= (ascii c) 48) (<= (ascii c) 57)))

;; T when S reads as a plain decimal number: digits, at most one dot,
;; at least one digit, nothing else.
(defun psd:len-num-p (s / i n c dots digits ok)
  (setq n (strlen s) i 1 dots 0 digits 0 ok T)
  (while (and ok (<= i n))
    (setq c (substr s i 1))
    (cond
      ((psd:len-digit-p c) (setq digits (1+ digits)))
      ((= c ".") (setq dots (1+ dots)))
      (T (setq ok nil)))
    (setq i (1+ i)))
  (and ok (> digits 0) (< dots 2)))

;; S cut on spaces, tabs and dashes, empty pieces dropped -- the
;; separators an inches part is written with, so "4 1/2" and "4-1/2"
;; come apart the same way.  It cuts a keyword list the same way.
(defun psd:len-split (s / i n c buf out)
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
(defun psd:len-token (tok / slash n d)
  (if (setq slash (vl-string-search "/" tok))
    (progn
      (setq n (substr tok 1 slash)
            d (substr tok (+ slash 2)))
      (if (and (psd:len-num-p n) (psd:len-num-p d) (/= (atof d) 0.0))
        (/ (atof n) (atof d))))
    (if (psd:len-num-p tok) (atof tok))))

;; The inches part of a measurement as a number of inches: every token
;; added up, so "4", "4.5", "4 1/2", "4-1/2" and "1/2" all read.  An
;; empty part is 0, which is how 4' reads as 4'-0".  nil when any
;; token is neither a number nor a fraction.
(defun psd:len-inches (s / toks total v tk)
  (setq toks (psd:len-split s) total 0.0)
  (foreach tk toks
    (if (and total (setq v (psd:len-token tk)))
      (setq total (+ total v))
      (setq total nil)))
  total)

;; Read a typed measurement as (INCHES HASFEET): the length in inches,
;; exactly as typed and NOT rounded, and T when feet were spelled --
;; carried through so the ruler is labelled in the family the length
;; was typed in.  Lenient, the way DIMSTAMP reads: the inch mark is
;; optional and may be two apostrophes, the dash after the feet mark is
;; optional, inches may be decimal, and a fraction may be spaced or
;; dashed -- 44, 44.5, 44 1/2, 4'4.5 and 4'-4 1/2" all read.  nil when
;; the text is not a measurement at all.
(defun psd:parse-len (s / n apos feetstr rest hasfeet feet inch)
  (setq s (vl-string-trim " \t" s)
        n (strlen s))
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
      (if (psd:len-num-p feetstr)
        (setq feet (atof feetstr) hasfeet T)
        (setq rest nil)))
    (setq rest (vl-string-trim " \t" s)))
  (setq inch (if rest (psd:len-inches rest)))
  (if (and inch (or hasfeet (/= rest "")))
    (list (+ (* feet 12.0) inch) hasfeet)))

;; INCHES to the nearest eighth, as an integer count of eighths -- the
;; unit the ruler is built in.
(defun psd:len-eighths (inches)
  (fix (+ 0.5 (* 8.0 inches))))

;; Spell TOTAL-EIGHTHS out as text, in the HASFEET family.  STACKED nil
;; is the PLAIN spelling ("44 1/2\"", what the command line says);
;; STACKED T is the DRAWN one, the fraction stacked through AutoCAD's
;; \S code at the size of the text around it, for a ruler label and
;; nothing else.
(defun psd:spell-len (total-eighths hasfeet stacked / feet remain whole f8
                         g num den fr)
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
             (T (strcat "{\\H1.0000x;\\S" (itoa num) "/" (itoa den) ";}"))))
  (strcat (if (and stacked (/= num 0)) "\\A1;" "")
          (if hasfeet (strcat (itoa feet) "'-") "")
          (itoa whole) fr "\""))

;; What to say when something typed is not a length at all.  The
;; examples are the lazy spellings on purpose: the ones worth showing
;; are the ones that save keystrokes.  A fraction is shown DASHED, never
;; spaced: at a click-or-type prompt the spacebar is Enter, so 44 1/2
;; entered 44 and handed the 1/2 to the next question as half an inch.
(defun psd:len-unread (v)
  (princ (strcat "\n\"" v "\" is not a length - try 44, 44.5, 44-1/2,"
                 " 4'4.5 or 4'-4-1/2\".")))

;; The RULER TIER an offset of OFFSET eighths from the current value
;; falls in -- 'jump for a whole inch, 'half/'quarter/'eighth for the
;; finer steps, biggest to smallest; a row's tick length and text
;; height read off it.
(defun psd:ruler-tier (offset / a m)
  (setq a (abs offset) m (rem a 8))
  (cond
    ((= m 0) 'jump)
    ((= m 4) 'half)
    ((member m '(2 6)) 'quarter)
    (T 'eighth)))

;; The nearby values to offer, as (EIGHTHS TIER) pairs: every eighth
;; for a whole inch either side, and with feet in play the 2" and 3"
;; jumps beyond that as well.  A row at or below zero is dropped.
;; Unsorted -- the ruler sorts once it also has the current row.
(defun psd:ruler-rows (total-eighths hasfeet / out i off)
  (setq out nil i 1)
  (while (<= i 8)
    (setq out (cons (list (- total-eighths i) (psd:ruler-tier i)) out))
    (setq out (cons (list (+ total-eighths i) (psd:ruler-tier i)) out))
    (setq i (1+ i)))
  (if hasfeet
    (progn
      (setq i 2)
      (while (<= i 3)
        (setq off (* i 8))
        (setq out (cons (list (- total-eighths off) 'jump) out))
        (setq out (cons (list (+ total-eighths off) 'jump) out))
        (setq i (1+ i)))))
  (vl-remove-if '(lambda (pr) (<= (car pr) 0)) out))

;; The RULER TIER a LADDER rung falls in, read off the value itself
;; rather than off a distance from the current row: a whole foot is the
;; deepest mark, a half foot the next, a quarter foot after that, and
;; everything else is a plain rung.  That is where a tape's deep marks
;; are, so a ladder of radii reads as a ruler and not as a list.
(defun psd:ladder-tier (eighths)
  (cond
    ((= 0 (rem eighths 96)) 'jump)        ; a whole foot
    ((= 0 (rem eighths 48)) 'half)        ; a half foot
    ((= 0 (rem eighths 24)) 'quarter)     ; a quarter foot
    (T 'eighth)))

;; The rungs of LADDER, given as (LO HI STEP) in inches: every step from
;; LO to HI, as the same (EIGHTHS TIER) pairs a tape's rows are.  A rung
;; at or below zero is dropped, as a tape's rows are.
;;
;; A ladder is a KNOB, and a knob is whatever a drafter left in it -- a
;; string, two numbers where three were wanted, a step of zero.  So the
;; shape is read here rather than trusted: anything that is not three
;; numbers with a positive step has no rungs, and psd:ruler-show reads
;; that as no ladder.  A settings line typed wrong costs the ruler, not
;; the command.  Unsorted -- the ruler sorts once it also has the
;; current row.
(defun psd:ladder-rows (ladder / lo hi step v out)
  (setq out nil)
  (if (and (= (type ladder) 'LIST) (= 3 (length ladder))
           (numberp (car ladder)) (numberp (cadr ladder))
           (numberp (caddr ladder)) (> (caddr ladder) 0.0))
    (progn
      (setq lo   (psd:len-eighths (car ladder))
            hi   (psd:len-eighths (cadr ladder))
            step (psd:len-eighths (caddr ladder))
            v    lo)
      (if (> step 0)
        (while (<= v hi)
          (if (> v 0) (setq out (cons (list v (psd:ladder-tier v)) out)))
          (setq v (+ v step))))))
  out)

;; Ascending by value -- the comparator the ruler sorts rows with.
(defun psd:ruler-val-lt (a b) (< (car a) (car b)))

;; What the screen is showing, as (LEFT BOTTOM WIDTH HEIGHT) in drawing
;; units: VIEWSIZE is the view's height and SCREENSIZE its aspect.
;; This is what pins the ruler to the same strip of screen at any zoom.
(defun psd:ruler-view ( / ctr vh ss aspect vw)
  (setq ctr (getvar "VIEWCTR")
        vh  (getvar "VIEWSIZE")
        ss  (getvar "SCREENSIZE"))
  (setq aspect (if (and ss (listp ss) (numberp (car ss))
                        (numberp (cadr ss)) (> (cadr ss) 0))
                 (/ (float (car ss)) (float (cadr ss)))
                 1.6))                    ; no viewport to measure
  (setq vw (* vh aspect))
  (list (- (car ctr) (/ vw 2.0)) (- (cadr ctr) (/ vh 2.0)) vw vh))

;; Which way a row reaches from a spine pinned SCREEN-X of the way
;; across the view: always toward the middle, so a ruler pinned near an
;; edge is never drawn past it.  1.0 toward higher x, -1.0 lower.
(defun psd:ruler-dir (screen-x)
  (if (> screen-x 0.5) -1.0 1.0))

;; Label height for a row of this TIER, against a row spacing of GAP,
;; the biggest label being FRAC of the spacing.
(defun psd:ruler-hgt (tier gap frac / base)
  (setq base (* gap frac))
  (cond
    ((eq tier 'half) (* base 0.8))
    ((eq tier 'quarter) (* base 0.65))
    ((eq tier 'eighth) (* base 0.5))
    (T base)))                     ; 'current and 'jump

;; Tick length for a row of this TIER, same measure.
(defun psd:ruler-tick (tier gap frac / base)
  (setq base (* gap frac))
  (cond
    ((eq tier 'half) (* base 0.75))
    ((eq tier 'quarter) (* base 0.55))
    ((eq tier 'eighth) (* base 0.35))
    (T base)))                     ; 'current and 'jump

;; The ruler is laid out in the UCS -- VIEWCTR is a UCS point, and so
;; is every click the hit test reads -- and entmake takes the WORLD.
;; So each point goes through trans on its way into the drawing: under
;; a UCS whose origin a drafter has moved to the pool's corner, the
;; ruler was drawn that far away from the view it was measured off,
;; out of sight, while the prompt still answered clicks on the empty
;; strip where it should have been.

;; A ruler stroke from (X1 Y1) to (X2 Y2) on LAY in ACI colour COL.
(defun psd:ruler-line (x1 y1 x2 y2 lay col)
  (entmakex (list '(0 . "LINE") '(100 . "AcDbEntity") (cons 8 lay)
                  (cons 62 col) '(100 . "AcDbLine")
                  (cons 10 (trans (list x1 y1 0.0) 1 0))
                  (cons 11 (trans (list x2 y2 0.0) 1 0)))))

;; The ring that marks the current row.
(defun psd:ruler-ring (x y r lay col)
  (entmakex (list '(0 . "CIRCLE") '(100 . "AcDbEntity") (cons 8 lay)
                  (cons 62 col) '(100 . "AcDbCircle")
                  (cons 10 (trans (list x y 0.0) 1 0)) (cons 40 r))))

;; A ruler label: one unwrapped MTEXT of height HGT at PT in the
;; current text style, attached top left (ATT 1) or top right (3) so
;; it grows away from the spine, and running along the UCS X axis
;; (group 11, a WORLD direction) so it reads level in a plan view of
;; that UCS.
(defun psd:ruler-label (pt hgt str lay col att)
  (entmakex (list '(0 . "MTEXT") '(100 . "AcDbEntity") (cons 8 lay)
                  (cons 62 col) '(100 . "AcDbMText")
                  (cons 10 (trans (list (car pt) (cadr pt) 0.0) 1 0))
                  (cons 40 hgt) '(41 . 0.0) (cons 71 att) '(72 . 5)
                  (cons 1 str) (cons 11 (trans '(1.0 0.0 0.0) 1 0 T))
                  '(73 . 1) '(44 . 1.0))))

;; Draw the ruler down its strip of the current view round
;; TOTAL-EIGHTHS, in the HASFEET family, on layer LAY, sized and
;; coloured by STYLE: one row per suggestion plus the ringed current
;; row among them, the whole thing centred vertically in the view.
;; LADDER nil is the tape, the eighths either side of TOTAL-EIGHTHS;
;; a (LO HI STEP) is the ladder, its rungs instead.  TOTAL-EIGHTHS may
;; be nil ON A LADDER and only there -- a ladder is the values a prompt
;; is answered with and stands whether or not one has been given yet,
;; where a tape is built round the last answer and has nothing to be
;; without it.  A rung equal to the current row is dropped, so the row
;; is ringed once rather than drawn twice.
;; Returns (ENTS BOX ROWS): the entities drawn, BOX as (XMIN XMAX YTOL)
;; for the hit test, and ROWS as (EIGHTHS ROW-Y) pairs.
(defun psd:draw-ruler (total-eighths hasfeet lay style ladder / rows n i row
                          val tier y hgt tl spx ents result view vx vy vw vh
                          gap base rcol dir far near)
  (setq rows (if ladder
               (vl-remove-if '(lambda (pr) (equal (car pr) total-eighths))
                             (psd:ladder-rows ladder))
               (psd:ruler-rows total-eighths hasfeet)))
  (if total-eighths
    (setq rows (cons (list total-eighths 'current) rows)))
  (setq rows (vl-sort rows 'psd:ruler-val-lt))
  (setq view (psd:ruler-view)
        vx   (car view)  vy (cadr view)
        vw   (caddr view) vh (cadddr view))
  (setq n    (length rows)
        gap  (* vh (nth 3 style))
        spx  (+ vx (* vw (nth 2 style)))
        dir  (psd:ruler-dir (nth 2 style))   ; rows run inward
        base (- (+ vy (/ vh 2.0)) (* gap (/ (- n 1) 2.0)))
        i    0
        ents nil
        result nil)
  (foreach row rows
    (setq val  (car row) tier (cadr row))
    (setq y    (+ base (* i gap))
          hgt  (psd:ruler-hgt tier gap (nth 4 style))
          tl   (psd:ruler-tick tier gap (nth 5 style))
          rcol (if (eq tier 'current) (nth 1 style) (nth 0 style)))
    (setq ents (cons (psd:ruler-line spx y (+ spx (* dir tl)) y lay rcol)
                     ents))
    ;; half a label's height above the tick puts it astride its own
    ;; row, and the attachment turns with the row: a label on a row
    ;; that reaches left is hung by its RIGHT edge, so it grows away
    ;; from the spine rather than back across it
    (setq ents (cons (psd:ruler-label (list (+ spx (* dir (+ tl (* gap 0.35))))
                                            (+ y (/ hgt 2.0)))
                                      hgt (psd:spell-len val hasfeet T)
                                      lay rcol (if (< dir 0.0) 3 1))
                     ents))
    (if (eq tier 'current)
      (setq ents (cons (psd:ruler-ring spx y (* gap (nth 6 style)) lay rcol)
                       ents)))
    (setq result (cons (list val y) result))
    (setq i (1+ i)))
  (setq ents (cons (psd:ruler-line spx base spx (+ base (* (- n 1) gap))
                                   lay (nth 0 style))
                   ents))
  ;; the strip a click counts as a pick in: the reach on the side the
  ;; rows run, half a spacing on the other -- the tick's own side
  (setq near (+ spx (* dir gap (nth 7 style)))
        far  (- spx (* dir (/ gap 2.0))))
  (list ents
        (list (min near far) (max near far) (/ gap 2.0))
        (reverse result)))

;; The row (if any) that PT lands on: inside the ruler's strip in X and
;; close enough in Y to one of ROWS.  Returns the row's EIGHTHS, or nil
;; when PT is empty space.
(defun psd:ruler-hit (pt box rows / r best bd d)
  (setq best nil bd nil)
  (if (and box (>= (car pt) (car box)) (<= (car pt) (cadr box)))
    (foreach r rows
      (setq d (abs (- (cadr pt) (cadr r))))
      (if (and (<= d (caddr box)) (or (null bd) (< d bd)))
        (setq best (car r) bd d))))
  best)

;; A ruler that is not up yet, to draw on LAY in STYLE.
(defun psd:ruler-new (lay style)
  (list nil nil nil nil nil lay style nil nil))

;; The ruler taken down: its entities erased and forgotten.  The family
;; and the hint flag are kept, since neither is about what is drawn; the
;; ladder is not, since it is what the next prompt asks for and the next
;; prompt says so itself.
;;
;; entdel refuses on a locked layer, and it refuses quietly -- so a
;; ruler that would not come down stayed in the drawing, and every
;; redraw added another.  The tools unlock their own ruler layer before
;; drawing on it; this is the line that says so if one gets through
;; anyway (the step routines draw on the current layer), once per
;; take-down, naming the layer the rows are left on.
(defun psd:ruler-off (state / e left)
  (setq left 0)
  (foreach e (nth 2 state)
    (if (and e (entget e) (not (entdel e))) (setq left (1+ left))))
  (if (> left 0)
    (princ (strcat "
  " (itoa left) " ruler item(s) could not be"
                   " erased - layer " (vl-princ-to-string (nth 5 state))
                   " is locked.  Unlock it and ERASE them.")))
  (list nil (nth 1 state) nil nil nil (nth 5 state) (nth 6 state)
        (nth 7 state) nil))

;; The ruler the next prompt stands beside: the tape round LEN when
;; LADDER is nil, the rungs of LADDER when it is not -- with LEN ringed
;; among them when there is one.  Drawn fresh when it is not up, or is
;; up round some other length or on some other ladder; left alone when
;; it already is what was asked for; taken down when neither is given,
;; since there is then nothing to build one out of.  Whether it is UP is
;; what is drawn, not what it stands round: a ladder with no answer yet
;; stands round nothing and is up all the same.
;; The one-line hint is said the first time a run draws one.
(defun psd:ruler-show (state len ladder / rr)
  ;; a ladder nothing can be built out of is no ladder at all, and is
  ;; dropped here rather than drawn as an empty one
  (if (and ladder (null (psd:ladder-rows ladder))) (setq ladder nil))
  (cond
    ((and (null len) (null ladder)) (psd:ruler-off state))
    ((and (nth 2 state) (equal (nth 0 state) len)
          (equal (nth 8 state) ladder)) state)
    (T
     (setq state (psd:ruler-off state))
     (setq rr (psd:draw-ruler (if len (psd:len-eighths len)) (nth 1 state)
                              (nth 5 state) (nth 6 state) ladder))
     (if (not (nth 7 state))
       (princ (strcat "\n  A ruler of " (if ladder "the usual" "nearby")
                      " lengths is beside the drawing: click a row to"
                      " take it, or type a length (44, 44-1/2, 3'8).")))
     (list len (nth 1 state) (car rr) (cadr rr) (caddr rr)
           (nth 5 state) (nth 6 state) T ladder))))

;; One length prompt beside the ruler in STATE, and every way of
;; answering it: Enter (nil back, for the caller to read as it always
;; did), a keyword out of KWS (handed back as the keyword), a typed
;; measurement in any spelling psd:parse-len reads, a click on a ruler
;; row (that row's value), or a click on empty space, which is the
;; first of two points to measure the length between.  Zero, a
;; negative and text that is not a length are refused and asked again,
;; as initget 6 used to refuse them.  Returns (VALUE STATE): the
;; answer, and the ruler as it now stands.
;;
;; READER is the one thing a caller can add to the reading: a function
;; of the typed string returning inches, for a spelling this tree reads
;; somewhere and the library does not -- SPA's "600mm".  It is tried
;; AFTER the standard spellings, so a measurement written the tree's
;; way still reads the tree's way at a prompt that has one, and what it
;; returns is refused on the same terms as anything else: zero and a
;; negative are not lengths whoever read them.  nil = no such spelling,
;; which is every caller but one.
;;
;; The caller SHOWS the ruler first -- (setq rl (psd:ruler-show rl last
;; ladder) rr (psd:ask-len prompt kws rl nil) v (car rr) rl (cadr rr)) --
;; and that order is not a nicety: an Esc inside this prompt runs the
;; caller's *error*, and what that handler can take down is the ruler
;; the CALLER's state names.  A ruler drawn in here, in a state only
;; this function held, would outlive the Esc.  The caller keeps the
;; state between prompts and takes the ruler down with psd:ruler-off
;; before a prompt that does not take it and on every way out.
(defun psd:ask-len (prompt kws state reader / pk v out done toks)
  (setq done nil out nil)
  (while (not done)
    (if kws (initget 128 kws) (initget 128))
    (setq pk (getpoint prompt))
    (if lzd:ask (lzd:ask prompt pk) pk)
    (cond
      ((null pk) (setq done T))
      ((= (type pk) 'STR)
       (cond
         ((member pk (psd:len-split (if kws kws ""))) (setq out pk done T))
         ;; a leading minus is refused here, since the reader treats a
         ;; dash as the separator in 4-1/2 and would read -5 as 5
         ((= (substr (vl-string-trim " \t" pk) 1 1) "-")
          (princ "\nA length must be more than zero."))
         ;; a fraction with nothing in front of it is almost always the
         ;; tail of 44 1/2 typed with a space -- which this prompt, a
         ;; getpoint, took as Enter after 44 -- landing on the NEXT
         ;; question.  Taken, it was half an inch there, and nothing
         ;; said so.  Refused, the drafter sees what happened and can
         ;; still give half an inch as 0-1/2 or .5
         ((and (= 1 (length (setq toks (psd:len-split
                                          (vl-string-trim " \t\"'" pk)))))
               (vl-string-search "/" (car toks)))
          (princ (strcat "\n\"" pk "\" on its own?  A space ends the answer"
                         " at this prompt - type 44-1/2, or 0-1/2 for half"
                         " an inch.")))
         ((setq v (psd:parse-len pk))
          (if (> (car v) 0.0)
            (progn
              (setq out (car v) done T)
              ;; a typed spelling picks the ruler's family -- feet typed
              ;; means feet on the ruler -- and a change relabels every
              ;; row, so the one standing is taken down here.  Down, not
              ;; forgotten: a ladder stands round no length, so there is
              ;; nothing for forgetting one to redraw
              (if (not (eq (cadr v) (nth 1 state)))
                (setq state (psd:ruler-off
                              (list (nth 0 state) (cadr v) (nth 2 state)
                                    (nth 3 state) (nth 4 state) (nth 5 state)
                                    (nth 6 state) (nth 7 state)
                                    (nth 8 state))))))
            (princ "\nA length must be more than zero.")))
         ((and reader (setq v (apply reader (list pk))))
          (if (and (numberp v) (> v 0.0))
            (setq out v done T)
            (princ "\nA length must be more than zero.")))
         (T (psd:len-unread pk))))
      ((setq v (psd:ruler-hit pk (nth 3 state) (nth 4 state)))
       (setq out (/ v 8.0) done T))
      (T
       (setq v (getdist pk "\nSecond point of the length: "))
       (if lzd:ask (lzd:ask "\nSecond point of the length: " v) v)
       (if (and (numberp v) (> v 0.0))
         (setq out v done T)
         (princ "\nA length must be more than zero.")))))
  (list out state))
;;; -------------------- end of the length ruler -------------------------

;; The scratch layer the rows are drawn on, made if it is missing.  A
;; layer of its own is what lets a drafter turn the ruler off without
;; turning anything of the section off with it, so OFF and FROZEN are left
;; the way they are found.  LOCKED is not: entmake draws onto a locked
;; layer but entdel refuses there, so every ruler drawn stayed in the
;; drawing for good and each redraw added another copy -- and LAYISO's
;; lock-and-fade locks this layer with everything else.  It is calofin
;; scratch, so it is unlocked, said once, and left unlocked.
(defun psd:rulerlayer ( / ed fl)
  (if (not (tblsearch "LAYER" psd:*ruler-layer*))
    (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord")
                   (cons 2 psd:*ruler-layer*) '(70 . 0) '(62 . 7)
                   (cons 6 "CONTINUOUS")))
    (progn
      (setq ed (entget (tblobjname "LAYER" psd:*ruler-layer*))
            fl (cdr (assoc 70 ed)))
      (if (and fl (= 4 (logand 4 fl))
               (entmod (subst (cons 70 (- fl 4)) (assoc 70 ed) ed)))
        (princ (strcat "\nPOOLSIDE: layer " psd:*ruler-layer*
                       " was locked - unlocked so the ruler can be"
                       " taken down again.")))))
  psd:*ruler-layer*)

;; Take the ruler down -- the one call *error* and the clean exit both
;; make, so neither has to know whether one was up.  What is left is
;; the swept STATE, not nil: it carries the one-line hint's said flag,
;; and a prompt that threw it away would say the hint again at the next
;; depth.  c:POOLSIDE clears it at the START of a run.
(defun psd:rulerkill ()
  (if psd:*ruler* (setq psd:*ruler* (psd:ruler-off psd:*ruler*))))

;; This file's knobs, in the order the ruler reads them.
(defun psd:ruler-style ()
  (list psd:*ruler-color* psd:*ruler-current-color* psd:*ruler-screen-x*
        psd:*ruler-row-frac* psd:*ruler-txt-frac* psd:*ruler-tick-frac*
        psd:*ruler-ring-frac* psd:*ruler-reach*))

;;; -------------------- form answers -----------------------------------
;;;
;;;  A form -- LAZSIDE, or the VB palette -- can answer some or all of
;;;  POOLSIDE's questions before the run starts.  It leaves them in
;;;  psd:*form* as (key . value) and the ask helpers below look there
;;;  first, so a filled-in sheet drives the whole run and a half-filled
;;;  one simply shortens it.  This is POOL's own store, same shape and
;;;  same three states, because the two tools ask for the same letters
;;;  and a sheet ought to mean the same thing to both.
;;;
;;;    key absent      the form did not answer it   -> ask, as usual
;;;    (key . nil)     the form answered NA         -> nil, no prompt
;;;    (key . 84.0)    the form answered it         -> 84.0, no prompt
;;;
;;;  (assoc key ...) tells those apart; (cdr (assoc ...)) alone cannot.
;;;
;;;  THE KEYS are the letters, lower-cased: b, c, d, c2 and one per run
;;;  (h g f e, or e2 f2 g f1 e1 on a Sport) -- psd:key is what spells
;;;  them, so the form and the prompts cannot drift.  style is the
;;;  bottom type, as one of the keywords psd:*btypes* lists, and mirror
;;;  is the Yes or No that swaps the section end for end.  The base
;;;  POINT is never form-answered: it is picked in the drawing with the
;;;  operator's own snaps live, which is the one thing a form cannot do
;;;  for them.
;;;
;;;  AN ANSWER IS REMOVED AS IT IS USED.  Not marked used -- removed.
;;;  Otherwise Back deadlocks: step back onto a form-answered question,
;;;  it answers itself instantly and walks forward again, and there is
;;;  no key to press to get out.  Consuming is also what gives the two
;;;  RANGE CHECKS their way out -- a D that is not deeper than C is
;;;  re-asked through psd:ask, and the second pass finds the store
;;;  empty and lets the operator type the correction rather than being
;;;  re-fed the same bad number for ever.

(setq psd:*form* nil)

;; Did the form answer KEY at all?  This is the absent/nil distinction
;; that (cdr (assoc ...)) throws away.
(defun psd:fhas (key) (if (assoc key psd:*form*) t nil))

;; The form's answer for KEY, removed from the store as it is read.
(defun psd:ftake (key / p)
  (setq p (assoc key psd:*form*))
  (setq psd:*form* (vl-remove p psd:*form*))
  (cdr p))

(defun psd:fclear () (setq psd:*form* nil))

;; The form's NUMBER for KEY, spent as it is read.  Anything that is
;; not a positive number is no answer at all: a sheet cannot talk the
;; run into a zero-length pool, and a nil here means NA, which every
;; caller of this one handles for itself.
(defun psd:fnum (key / v)
  (setq v (psd:ftake key))
  (if (and (numberp v) (> v 0.0)) v))

;; The canonical spelling of V in the space-separated list KWS, or nil
;; when it is not one of them -- so a word the live prompt would not
;; accept falls through to the prompt instead of being forced through.
(defun psd:fkword (v kws / i n c w out)
  (setq i 1 n (strlen kws) w "" v (strcase v))
  (while (<= i (1+ n))
    (setq c (if (<= i n) (substr kws i 1) " "))
    (if (= c " ")
        (progn
          (if (and (/= w "") (= (strcase w) v)) (setq out w))
          (setq w ""))
        (setq w (strcat w c)))
    (setq i (1+ i)))
  out)

;; The canonical spelling a KNOB's word stands for in the space-
;; separated list KWS, in any case, or nil for anything that is not one
;; of them -- a word, a number, nil.  The keyword knobs in the block at
;; the top are read through this: psd:askkw hands a default straight
;; back on Enter without checking it, so a word typed into a settings
;; box that the prompt would refuse must not reach the chain table
;; spelled its own way, and the caller falls back to the shipped one.
(defun psd:kwknob (v kws)
  (if (= (type v) 'STR) (psd:fkword v kws)))

;; The form's keyword for KEY against the live list KWS: the canonical
;; keyword, DFLT when the form said nil (what Enter means at every
;; keyword prompt here), or nil when the form did not answer -- which
;; is the caller's cue to ask.
(defun psd:fkw (key kws dflt / v)
  (if (psd:fhas key)
    (progn
      (setq v (psd:ftake key))
      (cond ((null v) dflt)
            ((and (= (type v) 'STR) (setq v (psd:fkword v kws))) v)))))

;; Run POOLSIDE with a form's answers already in hand.  Nothing here
;; is a command the operator types: a form sets psd:*form* itself and
;; calls c:POOLSIDE, which is what the tests do.
(defun psd:run-with-answers (answers)
  (setq psd:*form* answers)
  (c:POOLSIDE))

;; Keyword question.  kws is the initget string, shown the bracketed
;; list, dflt the Enter answer (nil = an answer is required).  Returns
;; the keyword or PSD-BACK.  Undo is a hidden synonym of Back.
(defun psd:askkw (msg kws shown dflt back / v)
  (initget (if dflt 0 (if back 0 1))
           (if back (strcat kws " Back Undo") kws))
  (setq v (getkword (strcat "\n" msg " [" shown
                            (if back "/Back" "") "]"
                            (if dflt (strcat " <" dflt ">") "") ": ")))
  (if lzd:ask (lzd:ask msg v) v)
  (cond ((member v '("Back" "Undo")) 'PSD-BACK)
        ((null v) (if dflt dflt (psd:askkw msg kws shown dflt back)))
        (t v)))

;; Yes/No that can be backed out of.  Returns T, nil or PSD-BACK.
(defun psd:askyn (msg dflt back / v)
  (setq v (psd:askkw msg "Yes No" "Yes/No" dflt back))
  (if (eq v 'PSD-BACK) v (= v "Yes")))

;; A plain required measurement, no guide highlight and no Back -- the
;; re-ask after a range check, where Back would step out of the check.
(defun psd:ask (msg ladder / v rr)
  (psd:osup)
  (if ladder
    (progn
      ;; the ruler goes up BEFORE the prompt and its state is the run's,
      ;; not a local: an Esc in here runs c:POOLSIDE's *error*, and what
      ;; that can take down is what c:POOLSIDE can see
      (setq v nil)
      (while (null v)
        (setq psd:*ruler*
                (psd:ruler-show (if psd:*ruler* psd:*ruler*
                                    (psd:ruler-new (psd:rulerlayer)
                                                   (psd:ruler-style)))
                                nil ladder)
              rr (psd:ask-len (strcat "\n" msg ": ") nil psd:*ruler* nil)
              v  (car rr)
              psd:*ruler* (cadr rr))
        (if (null v)
          (princ (strcat "\nA depth is required - type it, or click a"
                         " ruler row."))))
      (psd:rulerkill))
    (progn
      (initget 7)                       ; no null, no zero, no negative
      (setq v (getdist (strcat "\n" msg ": ")))
      (if lzd:ask (lzd:ask msg v) v)))
  (psd:osdown)
  v)

;; One prompt of a sequence, with the guide entities ents lit red while
;; it is asked.  kind is REQ (required), NAX (NA accepted) or ZER (NA
;; and zero accepted).  Returns the value, nil for NA, or PSD-BACK.
(defun psd:asks (kind msg ents back ladder / v cols kw e c prompt rr)
  (setq cols (mapcar 'psd:getcol ents))
  (foreach e ents (psd:setcol e psd:*hi-col*))
  (psd:osup)
  (setq kw (cond ((eq kind 'REQ) (if back "Back Undo" nil))
                 (back "NA Back Undo")
                 (t "NA")))
  ;; the prompt's TEXT is built once, above the fork, so the two routes
  ;; in cannot drift apart -- the form tests pin this wording
  (setq prompt (strcat "\n" msg
                       (if (eq kind 'REQ) "" " (or NA if not measured)")
                       (if back " [Back]" "")
                       ": "))
  ;; A ZER question admits a zero and the ruler's prompt does not -- no
  ;; length on a ruler is zero -- so a ladder handed to one is ignored
  ;; rather than quietly tightening what the question takes.  Only the
  ;; depths hand one in, and every depth is REQ.
  (if (and ladder (not (eq kind 'ZER)))
    (progn
      (setq v nil)
      (while (null v)
        (setq psd:*ruler*
                (psd:ruler-show (if psd:*ruler* psd:*ruler*
                                    (psd:ruler-new (psd:rulerlayer)
                                                   (psd:ruler-style)))
                                nil ladder)
              rr (psd:ask-len prompt kw psd:*ruler* nil)
              v  (car rr)
              psd:*ruler* (cadr rr))
        ;; Enter stays refused where initget 7 refused it
        (if (null v)
          (princ (strcat "\nA depth is required - type it, or click a"
                         " ruler row."))))
      ;; down before the answer is used: what follows a depth is another
      ;; question, and it asks for a ruler of its own if it wants one
      (psd:rulerkill))
    (progn
      ;; REQ always rejects zero - offering Back must not loosen what
      ;; counts as a valid measurement; ZER alone admits 0
      (if kw
          (initget (if (eq kind 'ZER) 5 7) kw)
          (initget 7))
      (setq v (getdist prompt))
      (if lzd:ask (lzd:ask msg v) v)))
  (psd:osdown)
  (mapcar '(lambda (e c) (psd:setcol e c)) ents cols)
  (cond ((and (= (type v) 'STR) (member v '("Back" "Undo"))) 'PSD-BACK)
        ((= (type v) 'STR) nil)               ; NA
        (t v)))

;;; -------------------- measurement sequence (Back) --------------------
;;;
;;;  Every question after the first offers Back, which re-asks the
;;;  previous one -- a typo no longer means Esc and start over.  Each
;;;  item is (key kind msg ents ladder), the last being the length
;;;  ruler's rungs where the question has a short list of answers and
;;;  nil where it does not.

(defun psd:sq (ans key) (cdr (assoc key ans)))

(defun psd:sqput (ans key v / out p)
  (foreach p ans (if (not (eq (car p) key)) (setq out (cons p out))))
  (reverse (cons (cons key v) out)))

;; Is V an answer this KIND of question would have accepted?  REQ
;; takes a positive measurement and nothing else; NAX takes that or NA
;; (nil); ZER takes zero as well.  These are the same three rules
;; psd:asks hands initget, written out so a FORM answer is held to
;; exactly what the prompt would have held it to -- a sheet cannot talk
;; the run into a negative run or a zero-length pool.
(defun psd:fok (kind v)
  (cond ((eq kind 'REQ) (and (numberp v) (> v 0.0)))
        ((eq kind 'ZER) (or (null v) (and (numberp v) (>= v 0.0))))
        (t              (or (null v) (and (numberp v) (> v 0.0))))))

(defun psd:askseq (items / ans i n it v asked)
  (setq ans nil i 0 n (length items) asked nil)
  (while (< i n)
    (setq it (nth i items))
    ;; THE FORM ANSWERS FIRST, and its answer is SPENT as it is read:
    ;; an answer the prompt would have refused is spent too and then
    ;; asked for properly, and stepping Back onto a form-answered
    ;; question finds the store empty and prompts, which is what keeps
    ;; Back from deadlocking on a filled-in sheet.
    (setq v (if (psd:fhas (car it)) (psd:ftake (car it)) 'PSD-ASK))
    (if (not (psd:fok (cadr it) v)) (setq v 'PSD-ASK))
    (if (eq v 'PSD-ASK)
      (setq v (psd:asks (cadr it) (caddr it) (cadddr it) (if asked t nil)
                        (nth 4 it))))
    (if (eq v 'PSD-BACK)
        ;; Back is not offered on the first question, so there is
        ;; always somewhere to step back to
        (if asked (setq i (car asked) asked (cdr asked)))
        (setq ans (psd:sqput ans (car it) v)
              asked (cons i asked)
              i (1+ i))))
  ans)

;; The form key a letter is stored under: "E2" -> e2, "H" -> h.
(defun psd:key (s) (read (strcase s t)))

;;; -------------------- the bottom types -------------------------------
;;;
;;;  Three tables, read together, are the whole of what separates one
;;;  bottom from another: the runs it is measured by, the depth each
;;;  station between them sits at, and the nominal proportions the
;;;  guide is drawn at before any answer is in.  POOL reaches the same
;;;  six shapes by pinning G and/or E to zero inside a plan routine;
;;;  with the plan gone there is nothing left to pin, so they are
;;;  simply listed.

;; The run chain, left to right, as (letter kind what-it-measures).
;; The runs always sum to B.
(defun psd:chain (style)
  (cond
    ((= style "Wedge")
     (list (list "H" 'NAX "left end to the deep line")
           (list "F" 'NAX "deep line to the right wall")))
    ((= style "SLope")
     (list (list "H" 'NAX "left end to the deep line")
           (list "F" 'NAX "deep line to the slope break")
           (list "E" 'NAX "slope break to the right end")))
    ((= style "MOdflat")
     (list (list "H" 'NAX "left end to the flat pad")
           (list "G" 'ZER "flat pad length")
           (list "F" 'NAX "pad to the right end")))
    ((= style "Sport")
     (list (list "E2" 'NAX "left end shallow flat")
           (list "F2" 'NAX "left slope")
           (list "G"  'ZER "deep flat length, 0 = no pad (V bottom)")
           (list "F1" 'NAX "right slope")
           (list "E1" 'NAX "right end shallow flat")))
    (t                                  ; Normal and SHallow
     (list (list "H" 'NAX "left end to the deep end")
           (list "G" 'ZER "hopper length, 0 = slope bottom")
           (list "F" 'NAX "deep end to the slope break")
           (list "E" 'NAX "slope break to the right end")))))

;; The depth every station sits at, left to right.  One entry MORE than
;; the chain has runs: the two wall bottoms are stations too.
;;   "c" wall height   "d" deep depth   "c2" break depth (SHallow only)
(defun psd:depths (style)
  (cond
    ((= style "Wedge")   (list "c" "d" "c"))
    ((= style "SLope")   (list "c" "d" "c" "c"))
    ((= style "MOdflat") (list "c" "d" "d" "c"))
    ((= style "Sport")   (list "c" "c" "d" "d" "c" "c"))
    ((= style "SHallow") (list "c" "d" "d" "c2" "c"))
    (t                   (list "c" "d" "d" "c" "c"))))

;; Guide proportions of B, before a single run has been answered
;; (POOL's pool:btmnom / pool:hopsport nominals, carried across).
(defun psd:nominal (style)
  (cond
    ((= style "Wedge")   (list 0.12 0.88))
    ((= style "SLope")   (list 0.12 0.58 0.30))
    ((= style "MOdflat") (list 0.10 0.70 0.20))
    ((= style "Sport")   (list 0.12 0.20 0.30 0.26 0.12))
    (t                   (list 0.12 0.20 0.40 0.28))))

;; Which run absorbs the difference when every one was given and they
;; still miss B: the pad where the style has one, the deep-end run
;; where it does not.  (POOL's slack member, same rule.)
(defun psd:slack (chain / i k n c)
  (setq i 0 k -1 n -1)
  (foreach c chain
    (if (= (car c) "G") (setq k i))
    (if (and (< n 0) (= (car c) "F")) (setq n i))
    (setq i (1+ i)))
  (if (>= k 0) k n))

;;; -------------------- resolving the chain ----------------------------
;;; Straight ports of pool:chainfix / pool:chainval, which is what makes
;;; a POOLSIDE section and a POOL section agree on the same field sheet.

;; Remove an item by index, returning the new list.
(defun psd:setnth (lst i val / k out v)
  (setq k 0 out nil)
  (foreach v lst
    (setq out (cons (if (= k i) val v) out)
          k (1+ k)))
  (reverse out))

;; Resolve a measurement chain against the total:
;;   * NA (nil) entries take the remainder -- split evenly when there
;;     is more than one
;;   * when every value is given but the sum misses the total, the
;;     slack member at index islack absorbs the difference
(defun psd:chainfix (vals total islack / sum n share out k v)
  (setq sum 0.0 n 0)
  (foreach v vals (if v (setq sum (+ sum v)) (setq n (1+ n))))
  (setq out nil k 0)
  (if (> n 0)
      (progn
        (setq share (/ (- total sum) n))
        (foreach v vals (setq out (cons (if v v share) out))))
      (foreach v vals
        (setq out (cons (if (and (= k islack)
                                 (> (abs (- sum total)) 1.0e-6))
                            (+ v (- total sum))
                            v)
                        out)
              k (1+ k))))
  (reverse out))

;; Post-check a resolved chain: no member may be negative.  One that
;; resolved below zero is lifted to a positive floor (12", or a share
;; of the total on a short pool) and the deficit comes out of the
;; LARGEST other member.  Returns (vals fixed); fixed holds the index
;; of every member changed -- the lifted one AND its donor -- so the
;; caller can draw their dims red and say so.
(defun psd:chainval (vals total / out fixed n i j v flo need big bigi w)
  (setq n (length vals)
        flo (min 12.0 (/ (abs total) (* 4.0 n)))
        out vals fixed nil i 0)
  (while (< i n)
    (setq v (nth i out))
    (if (< v -1.0e-6)
        (progn
          (setq need (- flo v) big -1.0e30 bigi nil j 0)
          (foreach w out
            (if (and (/= j i) (> w big)) (setq big w bigi j))
            (setq j (1+ j)))
          (setq out (psd:setnth (psd:setnth out i flo) bigi (- big need))
                fixed (append fixed (list i bigi)))))
    (setq i (1+ i)))
  (list out fixed))

;; Record a validation problem: a command-line warning now, and a red
;; note under the section later.
(defun psd:valnote (msg)
  (setq psd:*valnotes* (append psd:*valnotes* (list msg)))
  (princ (strcat "\n*** " msg " ***"))
  (princ))

;; The adjusted letters as "G/F" for that note.
(defun psd:fixnames (fixed labels / out i)
  (setq out "")
  (foreach i fixed
    (setq out (strcat out (if (= out "") "" "/") (nth i labels))))
  out)

;;; -------------------- the section ------------------------------------

;; The section as ((run . depth) ...), left to right, wall bottom to
;; wall bottom: the running sum of the chain against the depth list.
(defun psd:stations (style runs wh dp c2 / out r ds v)
  (setq ds (psd:depths style)
        r 0.0
        out (list (cons 0.0 (psd:depthof (car ds) wh dp c2)))
        ds (cdr ds))
  (foreach v runs
    (setq r (+ r v)
          out (cons (cons r (psd:depthof (car ds) wh dp c2)) out)
          ds (cdr ds)))
  (reverse out))

(defun psd:depthof (k wh dp c2)
  (cond ((= k "d") dp) ((= k "c2") c2) (t wh)))

;; The x of the first station carrying depth code CODE, read through
;; any mirror.  By CODE and not by depth value: with C2 answered equal
;; to C, a search by value would land on the wall instead of the break.
(defun psd:xcode (style sta code mir / ds i k c)
  (setq ds (psd:depths style) i 0 k nil)
  (foreach c ds
    (if (and (not k) (= c code)) (setq k i))
    (setq i (1+ i)))
  (if k (car (nth (if mir (- (length sta) 1 k) k) sta))))

;; The outline: waterline across the top, a wall of height C at each
;; end, and the floor through the stations between them.  A station
;; sitting exactly on its neighbour (G answered 0 -- a slope bottom, or
;; a sport V) repeats a point, so zero-length segments are dropped
;; rather than special-cased per style.
(defun psd:secdraw (total sta lay pvflag / pts prev p ink)
  ;; the fade/guide colour, resolved once for the whole run when this
  ;; is a preview pass: measuring it per segment would be a COM round
  ;; trip per segment
  (setq ink (if pvflag (psd:ink psd:*pv-col* 'guide)))
  (setq pts (append (list (list 0.0 0.0) (list total 0.0))
                    (mapcar '(lambda (s) (list (car s) (- (cdr s))))
                            (reverse sta))
                    (list (list 0.0 0.0)))
        prev (car pts))
  (foreach p (cdr pts)
    (if (> (distance prev p) 1.0e-6)
        (if pvflag
            (psd:pvadd (psd:pvline prev p ink))
            (psd:line prev p lay)))
    (setq prev p)))

;; The gray nominal section plus a lettered tie per question.  Returns
;; the highlight assoc: letter -> the entities lit while it is asked.
(defun psd:guide (style total doff th / nom whn dpn c2n runs sta pv y i seg xd xb)
  (setq nom (psd:nominal style)
        whn (* 0.09 total)              ; a nominal wall height and depth:
        dpn (* 0.20 total)              ; 43" and 96" on a 40' pool
        c2n (* 0.5 (+ whn dpn))
        runs (mapcar '(lambda (f) (* f total)) nom)
        sta (psd:stations style runs whn dpn c2n))
  (psd:secdraw total sta "POOL-NOTES" t)
  ;; the run chain, on one tie line below the nominal floor
  (setq y (- (+ dpn (* 0.9 doff))) i 0 pv nil)
  (foreach seg (psd:chain style)
    (setq pv (cons (psd:tie (list (car (nth i sta)) y)
                            (list (car (nth (1+ i) sta)) y)
                            (car seg) th)
                   pv)
          i (1+ i)))
  ;; and the depths: C off the right wall, D and C2 where they fall
  (setq xd (psd:xcode style sta "d" nil)
        xb (psd:xcode style sta "c2" nil)
        pv (cons (psd:tie (list (+ total (* 0.6 doff)) 0.0)
                          (list (+ total (* 0.6 doff)) (- whn)) "C" th)
                 pv)
        pv (cons (psd:tie (list xd 0.0) (list xd (- dpn)) "D" th) pv))
  (if xb
      (setq pv (cons (psd:tie (list xb 0.0) (list xb (- c2n)) "C2" th) pv)))
  pv)

;;; -------------------- dimensions -------------------------------------
;;;
;;;  Every dimension below is drawn in whatever dim style the drawing
;;;  already has current -- the standard one, in the drawings these
;;;  sections go into.  There is no small-dim style to switch to and
;;;  none to put back: see the note at the top of the file.

;; A horizontal / vertical dimension between two points.  The
;; orientation is STATED, not inferred from the points: a run is
;; measured between two floor points at different depths, and an
;; aligned dimension between those would read the slope instead.
(defun psd:dimh (p1 p2 pt)
  (command "_.DIMLINEAR" (psd:wp p1) (psd:wp p2) "_H" (psd:wp pt)))

(defun psd:dimv (p1 p2 pt)
  (command "_.DIMLINEAR" (psd:wp p1) (psd:wp p2) "_V" (psd:wp pt)))

;; Color the just-drawn dimension red (a measurement the validator had
;; to adjust).
(defun psd:dimred ( / e ed)
  (setq e (entlast))
  (if (and e (setq ed (entget e)))
      (entmod (if (assoc 62 ed)
                  (subst (cons 62 1) (assoc 62 ed) ed)
                  (append ed (list (cons 62 1)))))))

;; A LIMIT a refusal names, as the prompt will take it back: a maximum
;; floored and a minimum ceiled to the step a plain (rtos v) shows.
;; Rounded to nearest, a D of 72.22 read 6'-0 1/4" in the C2 refusal,
;; and the drafter who typed exactly that was refused again as too
;; deep.  The test stays on the true limit.
;; CALOFIN-LIB.lsp's cal:shown-step, cal:floor-shown and cal:ceil-shown are
;; these functions; the copies are here because a standalone file has to
;; load alone.
(defun psd:shown-step ( / p)
  (setq p (max 0 (min 8 (getvar "LUPREC"))))
  (if (member (getvar "LUNITS") '(4 5))
    (/ 1.0 (expt 2 p))
    (/ 1.0 (expt 10 p))))
(defun psd:floor-shown (v / s)
  (setq s (psd:shown-step))
  (* s (fix (+ (/ v s) 1e-9))))
(defun psd:ceil-shown (v / s n)
  (setq s (psd:shown-step)
        n (fix (+ (/ v s) 1e-9)))
  (* s (if (> (/ v s) (+ n 1e-9)) (1+ n) n)))

;;; -------------------- undo / sysvars ---------------------------------

;; One undo group per command, tracked in psd:*undo-open*.  It has to
;; be a GLOBAL: c:POOLSIDE pushes the error mode so its handler may
;; (command), and AutoCAD resets the evaluator before that handler
;; runs, so a local of the command reads nil in it.  With the flag a
;; local, an Esc at a depth prompt left the group open and the
;; drafter's next edits went into it -- one U then took them back with
;; the section.  It is set to nil at the top of every run, before the
;; group opens, so a flag left set by a run that died between its last
;; dim and the close can never let the next run's handler close a
;; group it never opened -- the fault POOL's and SPA's old shared
;; *undogrp* flags had.
;; Same body as cal:undobegin / cal:undoend, which the grouped build
;; swaps in:
;;   (setq psd:*undo-open* (psd:undobegin))
;;   ... (if psd:*undo-open* (setq psd:*undo-open* (psd:undoend))) ...
;; Opens only while undo is recording -- _Begin in a drawing with UNDO
;; off (bit 1 of UNDOCTL clear) errors out of the command -- and
;; returns nil then, so the idiom above skips the close it does not own.
(defun psd:undobegin ()
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn (command "_.UNDO" "_Begin") T)))

(defun psd:undoend ()
  (command "_.UNDO" "_End")
  nil)

;;; The snapshot lives in a GLOBAL and is taken only when no snapshot is
;;; already pending: if a previous run died before restoring, the stale
;;; snapshot still holds the user's TRUE settings.  Saving again there
;;; would capture the zeroed OSMODE and every later run would faithfully
;;; "restore" 0 -- the user's object snaps would look permanently wiped.

(defun psd:syssave ()
  (if (not psd:*sysold*)
      (setq psd:*sysold*
            (mapcar '(lambda (v) (cons v (getvar v)))
                    '("OSMODE" "LUNITS" "CMDECHO" "CLAYER")))))

(defun psd:sysrestore ( / v p)
  ;; OSMODE first -- object snaps are the setting the user misses most
  ;; if a run is ever cut short partway
  (foreach v '("OSMODE" "LUNITS" "CMDECHO" "CLAYER")
    (setq p (assoc v psd:*sysold*))
    (if p (setvar v (cdr p))))
  (setq psd:*sysold* nil))

;;; -------------------- main command -----------------------------------

(defun c:POOLSIDE ( / *error* style base total doff th chain pv ans
                      wh dp c2 runs cv fixed sta segs mir sgn i s p q
                      maxd ydim odl xc xd xb y m fv bdflt mdflt)

  (defun *error* (msg)
    (if (and msg
             (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
        (princ (strcat "\nPOOLSIDE error: " msg)))
    ;; user settings come back FIRST so nothing below can skip them
    (psd:sysrestore)
    ;; nothing to put DIMSTYLE back to: POOLSIDE never switches it
    (psd:pvkill)
    (psd:rulerkill)
    ;; the undo flag is a GLOBAL (see psd:undobegin): after the pushed
    ;; mode resets the evaluator, a local of c:POOLSIDE reads nil here
    (if psd:*undo-open* (setq psd:*undo-open* (psd:undoend)))
    (if *pop-error-mode* (*pop-error-mode*))
    (psd:fclear)                        ; both exits clear the form store
    (if lzd:report (lzd:report "POOLSIDE" *poolside-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "POOLSIDE" *poolside-version*))
  (if lzd:state (lzd:state '(psd:*form*)))

  (cond
    ;; a section cannot be laid out in a UCS that is tilted or upside
    ;; down (psd:ucsplan-p): said and stopped here, before anything is
    ;; asked, borrowed or drawn.  A form handed to this run goes with
    ;; it -- left standing, it would answer the next POOLSIDE typed at
    ;; the command line
    ((not (psd:ucsplan-p))
     (psd:ucsrefuse)
     (psd:fclear))
    (t
     ;; nothing is open yet: a flag an earlier run left set must not let
     ;; this run's handler close somebody else's undo group
     (setq psd:*undo-open* nil)

     ;; AutoCAD 2012+ requires this so *error* may call (command);
     ;; harmless no-op guard on older releases where it doesn't exist
     (if *push-error-using-command* (*push-error-using-command*))

     (psd:syssave)
     ;; a fresh run, so a fresh ruler: the hint is said once a run, and the
     ;; flag that says it has been said travels in here
     (setq psd:*valnotes* nil
           psd:*ruler* nil)
     (setvar "CMDECHO" 0)
     (setq psd:*undo-open* (psd:undobegin))
     ;; architectural units while prompting so every distance can be typed
     ;; as 25'6", 25'-6-1/2" or 25'6.5 as well as plain inches
     (setvar "LUNITS" 4)
     (princ "\nSide view only -- the floor dimensions, no plan.")
     (princ "\nDistances may be typed as 8'6\", 8'-6-1/2\" or 8'6.5 (plain numbers = inches).")

     ;; the bottom type and the base point are the two questions in front
     ;; of every measurement, so they are asked as a chain: Back at the
     ;; base point re-asks the type, which is the answer the rest of the
     ;; run is shaped by
     ;;
     ;; what Enter answers the bottom-type question with, read through
     ;; psd:kwknob so a knob the prompt would refuse leaves the shipped
     ;; "Normal" standing rather than reaching the chain table unspelled
     (setq bdflt (cond ((psd:kwknob psd:*btype-default* psd:*btypes*)) ("Normal")))
     (setq base 'RETRY)
     (while (eq base 'RETRY)
       ;; the form can name the bottom; anything psd:*btypes* does not
       ;; list falls through to the prompt rather than being forced in
       (if (null (setq style (psd:fkw 'style psd:*btypes* "Normal")))
         (setq style (psd:askkw "Bottom type" psd:*btypes* psd:*btshown*
                                bdflt nil)))
       ;; the base point is picked with the user's own snaps still live;
       ;; only afterwards do snaps drop for the command-fed drawing work.
       ;; It is the top LEFT of the section -- the waterline at the left
       ;; wall -- so the section hangs off a known corner.
       (initget "Back Undo")
       (setq base (getpoint "\nInsertion base point (top left of the section) [Back] <0,0>: "))
       (if lzd:ask (lzd:ask "\nInsertion base point (top left of the section) [Back] <0,0>: " base) base)
       (if (and (= (type base) 'STR) (member base '("Back" "Undo")))
         (progn (princ "\nStepping back one question.")
                (setq base 'RETRY))))
     (setq psd:*base* (if (and base (listp base))
                          (list (car base) (cadr base))
                          (list 0.0 0.0)))
     (setvar "OSMODE" 0)

     (psd:ensure-layer "POOL" 4)
     (psd:ensure-layer "DIMENSION" 2)
     (psd:ensure-layer "POOL-NOTES" 3)

     (setq total (if (setq fv (psd:fnum 'b))
                     fv
                     (psd:ask "B - overall length, wall to wall" nil))
           doff  (max 12.0 (/ total 18.0))
           th    (max 3.0 (/ total 70.0))
           chain (psd:chain style)
           pv    (psd:guide style total doff th))
     (command "_.ZOOM" "_Window"
              (psd:wp (list (- doff) (- (* 0.20 total) (* 3.0 doff))))
              (psd:wp (list (+ total (* 2.0 doff)) (* 2.0 doff))))
     (princ "\nFloor dimensions -- the RED tie is the one being asked for.")
     (princ "\n(after the first answer, Back re-asks the previous one)")

     (setq ans (psd:askseq (psd:items style chain pv))
           wh  (psd:sq ans 'c)
           dp  (psd:sq ans 'd)
           c2  (if (= style "SHallow") (psd:sq ans 'c2) wh))
     ;; the two range checks POOL makes: a deep end that is not deeper
     ;; than the wall is not a deep end, and the break sits between them
     (while (<= dp wh)
       (princ (strcat "\nD must be deeper than the wall height C ("
                      (rtos wh) ") -- re-enter."))
       (setq dp (psd:ask "D - deep end depth" psd:*deepdepth-ladder*)))
     (while (or (< c2 wh) (> c2 dp))
       (princ (strcat "\nC2 must be between C ("
                      (rtos (psd:ceil-shown wh)) ") and D ("
                      (rtos (psd:floor-shown dp)) ") -- re-enter."))
       (setq c2 (psd:ask "C2 - depth where the shallow floor meets the break"
                         psd:*breakdepth-ladder*)))
     (psd:pvkill)

     ;; resolve the runs against B: NA takes the remainder (split when
     ;; several), the slack member absorbs any leftover, and nothing is
     ;; allowed to come out negative
     (setq runs  (psd:chainfix (mapcar '(lambda (c) (psd:sq ans (psd:key (car c))))
                                       chain)
                               total (psd:slack chain))
           cv    (psd:chainval runs total)
           runs  (car cv)
           fixed (cadr cv))
     (if fixed
         (psd:valnote (strcat "FLOOR RUNS FAILED - "
                              (psd:fixnames fixed (mapcar 'car chain))
                              " ADJUSTED, VERIFY")))

     ;; the deep end is drawn on the left, the way the letters are
     ;; measured; mirroring swaps the section end for end and the run
     ;; dimensions with it, so the letters keep meaning what they meant
     ;; the form can answer it too, as the same Yes or No a click on the
     ;; bracket would send; anything else falls through to the prompt,
     ;; where psd:*mirror-default* is what Enter means -- read through
     ;; psd:kwknob on the same terms, so a knob that is not one of the two
     ;; words leaves "No" standing
     (setq mdflt (cond ((psd:kwknob psd:*mirror-default* "Yes No")) ("No"))
           fv  (psd:fkw 'mirror "Yes No" "No")
           mir (if fv
                   (= fv "Yes")
                   (psd:askyn "Put the deep end on the RIGHT?" mdflt nil))
           sgn (if mir -1.0 1.0)
           sta (psd:stations style runs wh dp c2)
           segs (psd:segs chain fixed))
     (if mir
         (setq sta (reverse (mapcar '(lambda (s) (cons (- total (car s)) (cdr s)))
                                    sta))
               segs (reverse segs)))

     (psd:secdraw total sta "POOL" nil)

     (setq odl (getvar "CLAYER"))
     (setvar "CLAYER" "DIMENSION")
     (setq maxd (apply 'max (mapcar 'cdr sta))
           ydim (- (+ maxd (* 1.4 doff))))
     ;; the overall above the waterline, the run chain on one baseline
     ;; below the floor
     (psd:dimh (list 0.0 0.0) (list total 0.0)
               (list (* 0.5 total) (* 1.0 doff)))
     (setq i 0)
     (foreach s segs
       (setq p (nth i sta) q (nth (1+ i) sta))
       (if (> (abs (- (car q) (car p))) 1.0e-6)
           (progn
             (psd:dimh (list (car p) (- (cdr p))) (list (car q) (- (cdr q)))
                       (list (* 0.5 (+ (car p) (car q))) ydim))
             ;; a run the validator had to move is drawn red, so the sheet
             ;; shows which number was not the crew's
             (if (cdr s) (psd:dimred))))
       (setq i (1+ i)))
     ;; the depths: C off the shallow wall, D at the deep end, C2 at the
     ;; break when the style has one
     (setq xc (if mir 0.0 total)
           xd (psd:xcode style sta "d" mir)
           xb (psd:xcode style sta "c2" mir))
     (psd:dimv (list xc 0.0) (list xc (- wh))
               (list (+ xc (* sgn 0.8 doff)) (* -0.5 wh)))
     (psd:dimv (list xd 0.0) (list xd (- dp))
               (list (- xd (* sgn 0.5 doff)) (* -0.5 dp)))
     (if xb
         (psd:dimv (list xb 0.0) (list xb (- c2))
                   (list (+ xb (* sgn 0.3 doff)) (* -0.5 c2))))
     (setvar "CLAYER" odl)

     ;; whatever had to be adjusted, in red under the section
     (setq y (- ydim (* 1.8 doff)))
     (foreach m psd:*valnotes*
       (psd:textc (list 0.0 y) (* 1.2 th) m "POOL-NOTES" 1)
       (setq y (- y (* 2.0 th))))

     (command "_.ZOOM" "_Window"
              (psd:wp (list (- (* 2.0 doff)) (- y (* 2.0 doff))))
              (psd:wp (list (+ total (* 3.0 doff)) (* 3.0 doff))))

     ;; the resolved chain, so what was read back off B is on the screen
     ;; as a number and not only as a dimension
     (princ (strcat "\n" style " side view -- B " (rtos total)))
     (setq i 0)
     (foreach s chain
       (princ (strcat "  " (car s) " " (rtos (nth i runs))))
       (setq i (1+ i)))
     (princ (strcat "  C " (rtos wh) "  D " (rtos dp)))
     (if (= style "SHallow") (princ (strcat "  C2 " (rtos c2))))

     (if psd:*undo-open* (setq psd:*undo-open* (psd:undoend)))
     (psd:sysrestore)
     (psd:rulerkill)
     (if *pop-error-mode* (*pop-error-mode*))
     (psd:fclear)))                        ; both exits clear the form store
  (if lzd:end (lzd:end "POOLSIDE"))
  (princ))

;; The question list: the run chain, then the depths.  ONE sequence, so
;; Back walks the lot -- a mistyped C steps back into the last run
;; rather than dropping the run.
(defun psd:items (style chain pv / out c)
  (foreach c chain
    (setq out (cons (list (psd:key (car c)) (cadr c)
                          (strcat (car c) " - " (caddr c))
                          (cdr (assoc (car c) pv)))
                    out)))
  ;; the three DEPTHS carry a ladder; the runs above them do not -- a
  ;; run is taped off the sheet and there is no short list of what one
  ;; comes to
  (setq out (cons (list 'd 'REQ "D - deep end depth" (cdr (assoc "D" pv))
                        psd:*deepdepth-ladder*)
                  (cons (list 'c 'REQ "C - wall height (shallow depth)"
                              (cdr (assoc "C" pv))
                              psd:*wallheight-ladder*)
                        out)))
  (if (= style "SHallow")
      (setq out (cons (list 'c2 'REQ
                            "C2 - depth where the shallow floor meets the break"
                            (cdr (assoc "C2" pv))
                            psd:*breakdepth-ladder*)
                      out)))
  (reverse out))

;; One entry per run, in chain order: (letter . T when the validator
;; had to adjust it), so its dimension can be drawn red.
(defun psd:segs (chain fixed / out i c)
  (setq i 0 out nil)
  (foreach c chain
    (setq out (cons (cons (car c) (if (member i fixed) t nil)) out)
          i (1+ i)))
  (reverse out))

(defun c:POOLSIDEVER ()
  (princ (strcat "\nPOOLSIDE " *poolside-version*))
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
(defun psd:selftests ()
  (list
    (list "chain of a Normal bottom runs H G F E"
          '(mapcar 'car (psd:chain "Normal"))  '("H" "G" "F" "E"))
    (list "depths has one station more than the chain has runs, every style"
          '(mapcar '(lambda (s) (- (length (psd:depths s)) (length (psd:chain s))))
                   '("Normal" "Sport" "Wedge" "SLope" "MOdflat" "SHallow"))
          '(1 1 1 1 1 1))
    (list "nominal proportions of a Sport bottom sum to 1"
          '(apply '+ (psd:nominal "Sport"))  1.0)
    (list "slack of a Sport chain is its pad G, at index 2"
          '(psd:slack (psd:chain "Sport"))  2)
    (list "chainfix splits the remainder over the NA runs"
          '(psd:chainfix '(10.0 nil nil) 40.0 0)  '(10.0 15.0 15.0))
    (list "chainfix hands a miss of B to the slack member"
          '(psd:chainfix '(10.0 10.0 10.0) 40.0 1)  '(10.0 20.0 10.0))
    (list "chainval lifts a negative run to the floor out of the largest"
          '(psd:chainval '(-4.0 30.0 10.0) 36.0)  '((3.0 23.0 10.0) (0 1)))
    (list "stations of a Wedge run C, D, C along the chain"
          '(psd:stations "Wedge" '(10.0 30.0) 42.0 84.0 nil)
          '((0.0 . 42.0) (10.0 . 84.0) (40.0 . 42.0)))
    (list "xcode finds the break by code, mirrored, with C2 equal to C"
          '(psd:xcode "SHallow"
                      (psd:stations "SHallow" '(10.0 20.0 30.0 40.0) 42.0 84.0 42.0)
                      "c2" T)  10.0)
    (list "kwknob spells a knob's sport as the prompt does"
          '(psd:kwknob "sport" psd:*btypes*)  "Sport")
    (list "fok: REQ refuses 0, ZER takes it, NAX takes NA"
          '(and (not (psd:fok 'REQ 0.0)) (psd:fok 'ZER 0.0) (psd:fok 'NAX nil)))
    (list "parse-len reads a bare 7' as 84 inches in feet"
          '(psd:parse-len "7'")  '(84.0 T))))

(foreach c '("POOLSIDE")
  (setq *calofin-selftests*
        (cons (cons c 'psd:selftests) *calofin-selftests*)))

;; Quiet inside the whole build: LAZPASS.lsp and
;; CALOFIN-LOADER.lsp set the flag while they load their members,
;; because one file's greeting is a greeting and sixty-three of
;; them is a wall the drafter scrolls past in every drawing they
;; open.  APPLOADed alone the flag is nil and this prints, which
;; is the one time somebody wants to be told.  CALVER reports the
;; whole roster whenever it is asked.
(if (not *calofin-quiet*)
  (princ (strcat "\nPOOLSIDE " *poolside-version*
                 " loaded.  Type POOLSIDE to run.")))
(princ)
