;;; ====================================================================
;;;  calofin.lsp -- support for the Calofin palette
;;;
;;;  The palette lists every routine in the toolset, but any given
;;;  drawing session has only loaded some of them.  Rather than offer a
;;;  button that fails, the palette asks here which commands actually
;;;  exist and greys out the rest.
;;;
;;;  This is the only Lisp the palette needs.  It draws nothing and
;;;  knows nothing about any routine beyond its name.
;;; ====================================================================

;; Every command the palette can show.  A name here that is not loaded
;; is simply reported as missing, so the list is safe to keep ahead of
;; whatever a given machine has.  One group per palette group, in the
;; palette's own order, so the two rosters can be compared by eye --
;; CommandCatalog.Groups in CalofinPalette.vb is the other half.
;;
;; The names are LAZPANEL's roster (lisp/lazpanel/LAZPANEL.lsp, the
;; rules in its header: headline commands only, no TUTORIAL*/VER/
;; RESCUE/CFG satellites, no DD* photo toolset, no LISPLAB) plus the
;; deprecated acady matcher pair the VB palette still carries buttons
;; for.  tests/test_shared.py checks every non-deprecated name here is
;; a real command in the grouped build, so this list can no longer sit
;; years behind the tree the way it once did.
(setq calofin:*commands*
  '(;; Layout
    "LAZFORM" "LAZTXT" "LAZFORMCOVER" "LAZSPA" "LAZSTEP" "SPA" "POOL"
    "POOLCOVER" "POOLSIDE" "POOLDEMO"
    "OASIS" "FITABHD" "FITABHDCOVER" "ABHD" "ABHDCOVER" "ADAB" "CABHD"
    "LHD" "PADDLE" "LINGUTTER" "LINGUTTERSCAN" "AUTOBEAD"
    "CORNERSTP" "HEMISTEP" "NORMIESTEP"
    "SMARTFILLET" "STOCKCOVER" "WCALST" "CUSTBLOCK"
    ;; Checking
    "CHECK" "DIMARCCHECK" "DIMCHECK" "DIMSCAN" "ABCURCHECK"
    "ABCURCHECKSCAN" "ABPCHECK" "LINCHECK" "LINFINCHECK" "LINFINSCAN"
    "LITELINFINSCAN" "COVERCHECK" "COVERSCAN" "LITECOVERSCAN"
    "SPACHECK" "SPACHECKSCAN" "LITESPACHECKSCAN" "LINTXTCHK"
    "CCPRECHECK"
    ;; Dimensions
    "AUTODIM" "AUTODIMSIDEPOV" "STAIRDIM" "FLOORDIM" "DIMCONTEND"
    "CDCREATE" "CDCALLOUT" "BPCALLOUT"
    ;; Points
    "ABCDEF" "ALTABCDEF" "XYPLOT" "ABFIND" "ABMOVE" "PERPPTS" "CPERPPTS"
    "XFTCONV" "POINTRENAMER" "CONSTELLATION" "SOCONV" "VSCONV"
    "DRONE" "TYDRN" "TYLERDRONESUITE"
    ;; deprecated but still shipped standalone (lisp/standards_checker/)
    "MATCHSTD" "ACADY-SCAN"))

;; Is C:<name> defined in this session?
;;
;; An unbound symbol evaluates to nil in AutoLISP, so reading the name
;; and evaluating it is enough -- no atoms-family scan, and it stays
;; correct for commands defined after this file was loaded.
(defun calofin:has (name)
  (if (eval (read (strcat "C:" name))) t nil))

;; The subset of calofin:*commands* that is loaded right now.  Called
;; from the palette; the returned list is what enables its buttons.
(defun calofin:loaded ( / out)
  (foreach n calofin:*commands*
    (if (calofin:has n) (setq out (cons n out))))
  (reverse out))

;;; ====================================================================
;;;  THE FORM WIRE
;;;
;;;  The palette collects TYPED TEXT and hands it here exactly as it was
;;;  typed.  Reading it is STANDARDS.md's three-state contract --
;;;
;;;      box left empty   the key is not sent -> the routine asks
;;;      NA typed in it   (key . nil) is sent -> the routine takes NA
;;;      a measurement    (key . 84.0)        -> that value, no prompt
;;;      anything else    the key is not sent -> the routine ASKS
;;;
;;;  -- and it is implemented once, here, rather than a second time in
;;;  VB.  That is not tidiness.  The palette used to parse the box
;;;  itself and accepted a plain decimal and nothing else, so
;;;
;;;      6'-3"
;;;
;;;  -- a spelling the DCL forms read perfectly, and which the form's
;;;  own hint tells the drafter to use -- produced no number, and the
;;;  palette sent (key . nil).  That is not "ask me": it is NA, the
;;;  measurement was recorded as not taken, and the routine never asked.
;;;  A wrong answer that looks answered, which is the exact failure
;;;  phase 3 of ui/UI-PLAN.md went after in the DCL forms.
;;;
;;;  distof is AutoCAD's own reader and knows every feet-and-inches
;;;  spelling there is.  Nothing should be re-deriving that in another
;;;  language.
;;; ====================================================================

;;  cal:trim's body.  A local copy because the palette must work at the
;;  standalone tier too -- APPLOAD POOL.LSP on its own and there is no
;;  CALOFIN-LIB.lsp to borrow from -- which is the same reason every
;;  standalone tool carries its own.  tests/test_palette_wire.py holds
;;  this copy to the library's, so it cannot drift.
(defun calofin:trim (s / i n)
  (if (null s) (setq s ""))
  (setq n (strlen s) i 1)
  (while (and (<= i n) (member (substr s i 1) '(" " "\t")))
    (setq i (1+ i)))
  (setq s (substr s i))
  (setq n (strlen s))
  (while (and (> n 0) (member (substr s n 1) '(" " "\t")))
    (setq s (substr s 1 (1- n)) n (1- n)))
  s)

;;  cal:formanswer's body, same copy rule.  'SKIP means "not answered",
;;  and it is what an unreadable box gives as well as an empty one --
;;  the routine asks, which is the only safe reading of text nobody can
;;  turn into a number.
(defun calofin:answer (v / n)
  (cond
    ((or (null v) (= v "")) 'SKIP)
    ((= (strcase (calofin:trim v)) "NA") nil)
    ((setq n (distof (calofin:trim v) 4)) n)
    ((setq n (distof (calofin:trim v) 2)) n)
    (t 'SKIP)))

;;  The keys whose text will be DROPPED: typed, but not readable as a
;;  measurement.  The palette's state line names these, and it has to
;;  name the same ones the wire drops or the line is a lie.  An empty
;;  box is not unreadable -- it is unanswered, which is a different
;;  thing and is counted separately.
(defun calofin:unreadable (measures / out v)
  (foreach p measures
    (setq v (cdr p))
    (if (and (/= (calofin:trim (if v v "")) "")
             (eq (calofin:answer v) 'SKIP))
        (setq out (cons (car p) out))))
  (reverse out))

;;  LITERALS travel as they are; MEASURES are typed text and are read.
;;
;;  The split is the palette's to make and it is not a detail: a shape
;;  word, a keyword answer and an insertion point are all strings or
;;  lists that the reader above would turn into 'SKIP and drop.  Run a
;;  "Rectangle" through a measurement reader and the shape stops
;;  travelling.
(defun calofin:form (literals measures / out a)
  (setq out (reverse literals))
  (foreach p measures
    (setq a (calofin:answer (cdr p)))
    (if (not (eq a 'SKIP)) (setq out (cons (cons (car p) a) out))))
  (reverse out))

;;  Hand a form to a routine.  FN is the entry point's name, so this
;;  file needs no knowledge of which routines have one; a name that is
;;  not defined in this session is reported rather than erroring, which
;;  is what LAZFORM does with the same question.
(defun calofin:run (fn literals measures / sym)
  ;; the SYMBOL is what apply wants, not the function value behind it:
  ;; (apply 'pool:run-with-answers (list form)) is the idiom, and it is
  ;; also the only spelling that survives a name defined after this
  ;; file was loaded
  (setq sym (read fn))
  (cond
    ((null (eval sym))
     (princ (strcat "\n" fn " is not loaded in this drawing."))
     (princ))
    (t (apply sym (list (calofin:form literals measures))))))

;; Convenience at the command line: report what is and is not loaded.
(defun c:CALOFIN-STATUS ( / have)
  (setq have (calofin:loaded))
  (princ (strcat "\nCalofin: " (itoa (length have)) " of "
                 (itoa (length calofin:*commands*)) " commands loaded."))
  (foreach n calofin:*commands*
    (if (not (member n have))
        (princ (strcat "\n  missing: " n))))
  (princ))

(princ "\ncalofin.lsp loaded.  CALOFIN opens the palette.")
(princ)
