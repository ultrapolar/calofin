;;; ======================================================================
;;; DIMSTAMP.lsp  --  click a point, stamp a feet/inch dimension text
;;;                    there, and repeat
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  DIMSTAMP       stamp dimension text, click after click
;;;            DIMSTAMPVER    print the loaded version
;;;
;;; Click a point and type the text once; it lands there as a TEXT
;;; entity.  Click again and the SAME text is offered by default --
;;; Enter repeats it -- or pick one of a short menu of nearby values,
;;; or type New to enter something else entirely; whichever you land
;;; on becomes what the NEXT click offers.  A listed value cannot be
;;; the AutoLISP keyword itself (a keyword may not contain a space, a
;;; quote or a slash), so the menu is numbered and the number's real
;;; value is printed right above the prompt that takes it.
;;;
;;; Every value is one of four forms, exactly -- nothing else parses:
;;;   34"                     whole inches
;;;   3'-4"                   feet and whole inches
;;;   34 1/2"                 inches and a fraction
;;;   3'- 4 1/2"              feet, inches and a fraction
;;;
;;; What the menu offers depends on which of the four the current text
;;; is:
;;;   * whole inches (34") -- every eighth of an inch from there up to
;;;     the next whole inch (34-1/8" ... 35"), simplified;
;;;   * feet and whole inches (3'-4"), no fraction -- quarter-inch
;;;     steps up and down (3'-3 3/4" ... 3'-4 3/4"), then whole-inch
;;;     jumps of 1", 2" and 3" on each side;
;;;   * either form WITH a fraction already in it (34 1/2" or
;;;     3'- 4 1/2") -- the same up-and-down-then-jump shape, but in
;;;     eighth-inch steps instead of quarters, since a value already
;;;     that precise deserves suggestions that precise.
;;; A suggestion that would come out at or below zero is dropped.
;;;
;;; Versioning: see tools/release_lisp.py at the repo root.  It reads
;;; *dimstamp-version* below and stamps a dated, REV-numbered twin of
;;; this file into releases/.
;;; ======================================================================

;;; -------------------- version ---------------------------------------
(setq *dimstamp-version* "v1.0")   ; announced on load; release_lisp.py
                                   ; reads this banner and stamps the
                                   ; dated twin in releases/ from it

;;; -------------------- tunables --------------------------------------
(setq ds:*layer* "DIMENSION")       ; layer the stamped text lands on --
                                    ; the same layer name ABFIND,
                                    ; CDCREATE and CDCALLOUT use for
                                    ; their own dimension text
(setq ds:*layer-color* 7)          ; ACI colour the layer is CREATED
                                    ; with -- 7 is AutoCAD's own
                                    ; black-on-white/white-on-black
                                    ; swap, so it reads on any screen
                                    ; without a measured 'auto knob.  A
                                    ; layer already in the drawing
                                    ; keeps its own colour
(setq ds:*text-hgt* 6.0)           ; TEXT height of every stamp

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

;; Parse a measurement string into (EIGHTHS HASFEET HASFRAC), where
;; EIGHTHS is the total value in eighths of an inch (an integer),
;; HASFEET is T when the text used feet notation and HASFRAC is T when
;; it already carried a fraction -- both drive ds:suggestions and are
;; carried back through so a value renders in the family it came in.
;; nil when S is not one of the four canonical forms in the header.
(defun ds:parse (s / n apos feetstr rest hasfeet feetnum spc wholestr
                    fracstr slash numstr denstr wholenum num den frac
                    hasfrac ok eighths)
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
  (setq wholenum 0 frac 0.0 hasfrac nil)
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
                      frac (/ (float num) (float den))
                      hasfrac T))))))))
  (if ok
    (progn
      (setq eighths (fix (+ 0.5 (* 8.0 (+ (* feetnum 12.0) wholenum frac)))))
      (list eighths hasfeet hasfrac))
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

;; The nearby values to offer, as an ascending list of TOTAL-EIGHTHS
;; integers (see the header banner for what each family offers); a
;; result at or below zero is dropped.
(defun ds:suggestions (total-eighths hasfeet hasfrac / step nearn out i)
  (setq out nil)
  (cond
    ((and (not hasfeet) (not hasfrac))
     ;; bare inches, no fraction yet: every eighth up to the next
     ;; whole inch (34" suggests 34-1/8" ... 35")
     (setq i 1)
     (while (<= i 8)
       (setq out (cons (+ total-eighths i) out))
       (setq i (1+ i))))
    (T
     (setq step (if (and hasfeet (not hasfrac)) 2 1))   ; 1/4" or 1/8"
     (setq nearn (if (= step 2) 3 7))                   ; up to 3/4" or 7/8"
     (setq i 1)
     (while (<= i nearn)
       (setq out (cons (- total-eighths (* i step)) out))
       (setq out (cons (+ total-eighths (* i step)) out))
       (setq i (1+ i)))
     (setq i 1)
     (while (<= i 3)                                    ; then 1, 2, 3 inches
       (setq out (cons (- total-eighths (* i 8)) out))
       (setq out (cons (+ total-eighths (* i 8)) out))
       (setq i (1+ i)))))
  (setq out (vl-remove-if '(lambda (x) (<= x 0)) out))
  (vl-sort out '<))

;; "1 2 3 ... N" -- the numbered keywords the suggestion menu offers,
;; one per entry in the list ds:suggestions handed back.
(defun ds:num-keywords (n / s i)
  (setq s "" i 1)
  (while (<= i n)
    (setq s (strcat s (if (= i 1) "" " ") (itoa i)))
    (setq i (1+ i)))
  s)

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

;; Write STR at P.
(defun ds:draw-text (p str)
  (entmakex (list '(0 . "TEXT") '(100 . "AcDbEntity")
                  (cons 8 ds:*layer*) '(100 . "AcDbText")
                  (cons 10 (list (car p) (cadr p) 0.0))
                  (cons 40 ds:*text-hgt*)
                  (cons 1 str))))

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

;; The very first text of a run: no default, no suggestions -- nothing
;; exists yet to compare against.
(defun ds:ask-first ()
  (ds:ask-raw "\nText, e.g. 34\", 3'-4\", 34 1/2\" or 3'- 4 1/2\": "))

;; The second-and-later prompt: Enter repeats LASTTEXT, a listed number
;; picks a nearby value, New asks fresh through ds:ask-raw.  Always
;; returns a valid measurement string.
(defun ds:ask-next (lasttext / parsed sugg kws fullkws bracket i v idx
                             newv)
  (setq parsed (ds:parse lasttext))
  (setq sugg (ds:suggestions (car parsed) (cadr parsed) (caddr parsed)))
  (if sugg
    (progn
      (princ "\nNearby values:")
      (setq i 1)
      (foreach v sugg
        (princ (strcat "\n  " (itoa i) "  " (ds:format v (cadr parsed))))
        (setq i (1+ i)))))
  (setq kws (ds:num-keywords (length sugg)))
  (setq fullkws (if (= kws "") "New" (strcat kws " New")))
  (setq bracket (vl-string-translate " " "/" fullkws))
  (initget fullkws)
  (setq idx (getkword (strcat "\nText [" bracket "] <repeat \"" lasttext
                              "\">: ")))
  (if lzd:ask (lzd:ask "ds:ask-next" idx))
  (cond
    ((null idx) lasttext)
    ((= idx "New")
     (ds:ask-raw (strcat "\nNew text, e.g. 34\", 3'-4\", 34 1/2\" or"
                         " 3'- 4 1/2\": ")))
    (T
     (setq newv (nth (1- (atoi idx)) sugg))
     (ds:format newv (cadr parsed)))))

;;; -------------------- the command ------------------------------------
;; NOTE: no local here may be named after a function this routine
;; calls - an AutoLISP local SHADOWS the function of the same name for
;; the whole call, so a local called "last" turns every (last ...) in
;; the body into "no function definition: LAST" at runtime.
(defun c:DIMSTAMP (/ *error* undo-open pk lasttext newtext count)
  (defun *error* (msg)
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
                 " - click a point, then give the text; Enter when done."))
  (setq lasttext nil count 0)
  (while (setq pk (getpoint
                    "\nClick a point to place text (Enter when done): "))
    (setq newtext (if lasttext (ds:ask-next lasttext) (ds:ask-first)))
    (ds:ensure-layer ds:*layer* ds:*layer-color*)
    (ds:draw-text pk newtext)
    (setq lasttext newtext count (1+ count))
    (princ (strcat "\n  \"" newtext "\" placed.")))

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
