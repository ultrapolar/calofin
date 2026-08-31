;;; ===================================================================
;;; CCPRECHECK.LSP - Tech drawing checklist walker
;;;
;;; Interactive AutoLISP routine that walks the "Tech Flow Chart"
;;; decision tree for pool/spa products.  Load with APPLOAD (or
;;; (load "ccprecheck.lsp")) and run the CCPRECHECK command.  The routine asks
;;; the user to answer / confirm each item along the flowchart until
;;; every branch it enters reaches its end, then prints a summary of
;;; every note and confirmation that was collected on the way.
;;;
;;; Every question after the first also offers Back (Undo is accepted
;;; as a hidden synonym), which re-asks the previous question and drops
;;; what it logged - including backing OUT of a sub-branch into the
;;; question that opened it, and changing an answer re-routes the walk.
;;; At the typed Confirm prompts Back is typed like a note: B, BACK, U
;;; or UNDO alone, any case.
;;;
;;; Flow (top level):
;;;   Product Type
;;;     +- Liner      -> Pool | Spa
;;;     +- Pool Cover -> Freeform | Rectangle
;;;     +- Spa Cover  -> Safety Cover | Hard Cover | ThermoLight Cover
;;; ===================================================================

;;; ------------------------------------------------------------------
;;; Helpers
;;; ------------------------------------------------------------------

(setq *ccprecheck-version* "v1.3")   ; announced on load; release_lisp.py
                                        ; stamps the dated twin in releases/

(setq *chk:log* nil)   ; collected checklist lines for the summary

(setq *chk:prev* nil)  ; each question's previous answer, keyed by its
                       ; exact prompt text.  Session memory on purpose:
                       ; it only ever supplies a <default> the user must
                       ; still Enter through, never an answer by itself,
                       ; so a re-run over the same job is Enter-Enter
                       ; down the unchanged questions

;; Record a line for the final summary.
(defun chk:log (msg)
  (setq *chk:log* (append *chk:log* (list msg)))
  msg
)

;; Keep only the first N summary lines - the rollback when a Back
;; drops what a question and its branch logged.
(defun chk:trim (n / out i)
  (setq out nil i 0)
  (foreach l *chk:log*
    (if (< i n) (setq out (cons l out)))
    (setq i (1+ i))
  )
  (setq *chk:log* (reverse out))
)

;; T when a typed string means "go back a step" - getstring prompts
;; cannot take initget keywords, so Back is typed like a note.
(defun chk:back-word (s)
  (member (strcase s) '("B" "BACK" "U" "UNDO"))
)

;; Print an instruction/note to the command line and log it.
(defun chk:note (msg)
  (princ (strcat "\n  >> " msg))
  (chk:log (strcat "NOTE: " msg))
  msg
)

;; Ask the user to pick one keyword out of a list.
;; kwlist  - initget-style keyword string, e.g. "Yes No"
;; prompt  - question text (keywords appended automatically)
;; back    - non-nil: also offer Back (Undo accepted too), returning
;;           the symbol CHK-BACK
;; Returns the chosen keyword string (loops until a choice is made).
;; The first time a question is ever asked Enter is rejected - the
;; checklist stays deliberate - but its answer is remembered in
;; *chk:prev*, so every later ask offers it as the <default>.
(defun chk:ask (prompt kwlist back / ans dflt)
  (setq dflt (cdr (assoc prompt *chk:prev*)))
  (while (not ans)
    (initget (if dflt 0 1)
             (if back (strcat kwlist " Back Undo") kwlist))
    (setq ans (getkword (strcat "\n" prompt " ["
                                (vl-string-translate " " "/" kwlist)
                                (if back "/Back" "") "]"
                                (if dflt (strcat " <" dflt ">") "") ": ")))
    (if (and (null ans) dflt) (setq ans dflt))
  )
  (if (member ans '("Back" "Undo"))
    'CHK-BACK
    (progn (setq *chk:prev* (cons (cons prompt ans) *chk:prev*))
           (chk:log (strcat prompt " -> " ans)) ans)
  )
)

;; Yes/No convenience wrapper.  Returns T for Yes, nil for No, or the
;; symbol CHK-BACK.
(defun chk:yesno (prompt back / v)
  (setq v (chk:ask prompt "Yes No" back))
  (if (eq v 'CHK-BACK) v (= v "Yes"))
)

;; Ask the user to confirm an item; optionally record a typed-in value.
;; With back non-nil, B (Back) returns the symbol CHK-BACK instead.
(defun chk:confirm (item back / val)
  (setq val (getstring T (strcat "\nConfirm " item
                                 " (type value/notes"
                                 (if back ", B = back" "")
                                 " or press Enter): ")))
  (cond
    ((and back (chk:back-word val)) 'CHK-BACK)
    ((= val "") (chk:log (strcat "CONFIRMED: " item)) val)
    (T (chk:log (strcat "CONFIRMED: " item " = " val)) val)
  )
)

;; Run a flowchart node as a list of stages with Back between them.
;; Each stage is (test-expr . fn): a stage whose test evaluates nil is
;; skipped, and tests are re-evaluated on every pass, so backing up and
;; changing an answer re-routes the branch.  A stage returning CHK-BACK
;; rewinds to the previous asked stage, dropping everything logged
;; since just before it.  Backing out of the FIRST asked stage returns
;; CHK-BACK to the caller when bk is non-nil (the parent then re-asks
;; the question that opened this branch); with bk nil it re-asks.
(defun chk:seq (fns bk / i n v it asked mark out)
  (setq i 0 n (length fns) asked nil out nil)
  (while (and (< i n) (not out))
    (setq it (nth i fns))
    (if (and (car it) (not (eval (car it))))
      (setq i (1+ i))                       ; branch not taken - skip
      (progn
        (setq mark (length *chk:log*)
              v    (apply (cdr it) nil))
        (cond
          ((eq v 'CHK-BACK)
           (chk:trim mark)                  ; drop the aborted stage's log
           (if asked
             (progn
               (setq i (caar asked))
               (chk:trim (cdar asked))
               (setq asked (cdr asked))
             )
             (if bk
               (setq out T)                 ; backed out of this branch
               (princ "\n  Already at the first question.")
             )
           ))
          (T
           (setq asked (cons (cons i mark) asked)
                 i     (1+ i))
          )
        )
      )
    )
  )
  (if out 'CHK-BACK nil)
)

;;; ------------------------------------------------------------------
;;; Liner branch
;;; ------------------------------------------------------------------

;; Steps? sub-flow (shared by Liner->Pool and Liner->Spa)
(defun chk:steps (/ st kind v)
  (chk:seq
    (list
      (cons nil '(lambda ()
        (setq v (chk:yesno "Steps?" T))
        (if (not (eq v 'CHK-BACK))
          (progn
            (setq st v)
            (if (not st) (chk:note "No need to show any step info"))
          )
        )
        v))
      (cons 'st '(lambda ()
        (setq v (chk:ask "Step type" "Fiberglass VinylOver" T))
        (if (= v "VinylOver") (chk:note "Show Step Attachment & Risers"))
        (if (not (eq v 'CHK-BACK)) (setq kind v))
        v))
      (cons '(and st (= kind "Fiberglass")) '(lambda ()
        (setq v (chk:confirm "the step face is either straight or radius" T))
        (if (not (eq v 'CHK-BACK))
          (chk:note "Show the location of the step always")
        )
        v))
      (cons '(and st (= kind "Fiberglass")) '(lambda ()
        (chk:confirm "the size of the step (especially for radius steps)" T)))
      (cons '(and st (= kind "VinylOver")) '(lambda ()
        (chk:confirm "sum of Step Risers equals Wall Height" T)))
      (cons '(and st (= kind "VinylOver")) '(lambda ()
        (chk:confirm "Step Back Corners" T)))
    )
    T
  )
)

(defun chk:liner-pool ()
  (chk:seq
    (list
      (cons nil '(lambda () (chk:confirm "Liner Pattern" T)))
      (cons nil '(lambda () (chk:confirm "Pool Corners" T)))
      (cons nil '(lambda () (chk:confirm "Depth / Wall Height" T)))
      (cons nil '(lambda () (chk:steps)))
    )
    T
  )
)

(defun chk:liner-spa (/ spill v)
  (chk:seq
    (list
      (cons nil '(lambda () (chk:confirm "Liner Pattern" T)))
      (cons nil '(lambda () (chk:confirm "the corners" T)))
      (cons nil '(lambda () (chk:confirm "Depth / Wall Height" T)))
      (cons nil '(lambda ()
        (setq v (chk:yesno "Spillway?" T))
        (if (not (eq v 'CHK-BACK))
          (progn
            (setq spill v)
            (if spill
              (chk:note "Show Spillway Detail confirming Bead location")
              (chk:note "Show nothing for the spillway")
            )
          )
        )
        v))
      (cons 'spill '(lambda ()
        (chk:confirm "Spillway Dimensions and location" T)))
      (cons nil '(lambda () (chk:steps)))
    )
    T
  )
)

(defun chk:liner (/ lfor v)
  (chk:seq
    (list
      (cons nil '(lambda ()
        (setq v (chk:ask "Liner for" "Pool Spa" T))
        (if (not (eq v 'CHK-BACK)) (setq lfor v))
        v))
      (cons nil '(lambda ()
        (if (= lfor "Pool") (chk:liner-pool) (chk:liner-spa))))
    )
    T
  )
)

;;; ------------------------------------------------------------------
;;; Pool Cover branch
;;; ------------------------------------------------------------------

;; Obstruction sub-flow (also referenced from Spa Cover -> Safety Cover)
(defun chk:obstruction (/ prox sec big v)
  (chk:seq
    (list
      (cons nil '(lambda ()
        (setq v (chk:ask
          "Proximity to water's edge"
          "MoreThan3ft OverlapTo3ft ZeroToOverlap InsidePerimeter" T))
        (if (not (eq v 'CHK-BACK))
          (progn
            (setq prox v)
            (cond
              ((= prox "MoreThan3ft") (chk:note "Treatment not necessary"))
              ((= prox "OverlapTo3ft") (chk:note "Avoid strap"))
              ((= prox "ZeroToOverlap")
               ;; 0" meaning the obstruction defines the pool perimeter
               (chk:note "0\" means the obstruction defines the pool perimeter"))
            )
          )
        )
        v))
      (cons '(= prox "ZeroToOverlap") '(lambda ()
        (setq v (chk:yesno "Can the cover be secured to the obstruction?" T))
        (if (not (eq v 'CHK-BACK))
          (progn
            (setq sec v)
            (if sec (chk:note "Most of the time Cable, unless stated otherwise"))
          )
        )
        v))
      (cons '(and (= prox "ZeroToOverlap") (not sec)) '(lambda ()
        (setq v (chk:yesno "Is the obstruction larger than 36\"?" T))
        (if (not (eq v 'CHK-BACK))
          (progn
            (setq big v)
            (if (not big)
              (chk:note (strcat "CutOut if it is a viable solution - "
                                "if not, then reduced overlap and/or shortened springs"))
            )
          )
        )
        v))
      (cons '(and (= prox "ZeroToOverlap") (not sec) big) '(lambda ()
        (setq v (chk:yesno "Able to go over the obstruction?" T))
        (if (not (eq v 'CHK-BACK))
          (if v
            (progn
              (chk:note "Up and Over")
              (chk:note "3x3 padding over obstacle & step riser where necessary")
            )
            (chk:note "Reduced overlap and/or shortened springs")
          )
        )
        v))
      (cons '(= prox "InsidePerimeter") '(lambda ()
        ;; obstruction resides completely inside pool perimeter
        (setq v (chk:yesno "Able to go over the obstruction?" T))
        (if (not (eq v 'CHK-BACK))
          (if v
            (progn
              (chk:note "Up and Over")
              (chk:note "3x3 padding over obstacle")
            )
            (chk:note "Boot CutOut")
          )
        )
        v))
    )
    T
  )
)

(defun chk:decking (/ mat raised canedge v)
  (chk:seq
    (list
      (cons nil '(lambda ()
        (setq v (chk:ask "Decking material" "Concrete Paver Grass Wood" T))
        (if (not (eq v 'CHK-BACK))
          (progn
            (setq mat v)
            (cond
              ((= mat "Concrete") (chk:note "Standard Anchors / Tubes"))
              ((= mat "Paver")    (chk:note "9\" Tubes / 15\" Tubes"))
              ;; grass / planter / rocks
              ((= mat "Grass")    (chk:note "Tubes / Lawn Stakes / 2x2 Stakes"))
              (T                  (chk:note "Wood Deck Anchors"))
            )
          )
        )
        v))
      (cons '(= mat "Wood") '(lambda ()
        (setq v (chk:yesno "Is the decking raised?" T))
        (if (not (eq v 'CHK-BACK))
          (progn
            (setq raised v)
            (if (not raised) (chk:note "Wood Deck Anchors"))
          )
        )
        v))
      (cons '(and (= mat "Wood") raised) '(lambda ()
        (setq v (chk:yesno "Are you able to secure the cover to the edge of the deck?" T))
        (if (not (eq v 'CHK-BACK))
          (progn
            (setq canedge v)
            (if canedge
              (chk:note "On Ground Bracket Clamps / Wood Deck Anchors")
              (chk:note "Wood Deck Anchors")
            )
          )
        )
        v))
      (cons '(and (= mat "Wood") raised (not canedge)) '(lambda ()
        (setq v (chk:ask "Strap type" "ExtendedStraps ExtensionStraps" T))
        (if (not (eq v 'CHK-BACK))
          (if (= v "ExtendedStraps")
            (chk:note "Extended Straps: attached to the pool cover, can be any length")
            (progn
              (chk:note "Extension Straps: connect to the straps on the cover")
              (chk:note "Extension Straps come in 2'-0\", 4'-0\" and 6'-0\"")
            )
          )
        )
        v))
      ;; Deck space and springs
      (cons nil '(lambda ()
        (setq v (chk:ask "Deck space (for springs)"
                         "GreaterThan18in 9to18in 6to9in LessThan4in" T))
        (if (not (eq v 'CHK-BACK))
          (cond
            ((= v "GreaterThan18in") (chk:note "Standard Springs"))
            ((= v "9to18in")         (chk:note "Short Springs"))
            ((= v "6to9in")          (chk:note "Special Deck Mount"))
            (T                       (chk:note "D-Ring"))
          )
        )
        v))
    )
    T
  )
)

(defun chk:pool-cover (/ obst v)
  (chk:seq
    (list
      (cons nil '(lambda ()
        (setq v (chk:ask "Pool shape" "Freeform Rectangle" T))
        (if (not (eq v 'CHK-BACK))
          (if (= v "Freeform")
            (chk:note "18\" overlap, 3x3 spacing unless stated otherwise")
            (chk:note "12\" overlap, 5x5 spacing unless stated otherwise")
          )
        )
        v))
      (cons nil '(lambda ()
        (setq v (chk:confirm "Overlap and Spacing" T))
        (if (not (eq v 'CHK-BACK)) (chk:note "Pad sharp corners"))
        v))
      (cons nil '(lambda ()
        (setq v (chk:yesno "Are there obstacles?" T))
        (if (not (eq v 'CHK-BACK))
          (progn
            (setq obst v)
            (if obst (chk:note "Treat obstacles accordingly"))
          )
        )
        v))
      (cons 'obst '(lambda () (chk:obstruction)))
      (cons nil '(lambda () (chk:decking)))
    )
    T
  )
)

;;; ------------------------------------------------------------------
;;; Spa Cover branch
;;; ------------------------------------------------------------------

(defun chk:spa-safety (/ obst raised attach v)
  (chk:seq
    (list
      (cons nil '(lambda ()
        (setq v (chk:yesno "Spillway?" T))
        (if (and (not (eq v 'CHK-BACK)) v)
          (chk:note "Pad & dimension the spillway")
        )
        v))
      (cons nil '(lambda ()
        (setq v (chk:yesno "Obstructions?" T))
        (if (not (eq v 'CHK-BACK))
          (progn
            (setq obst v)
            (if obst
              (chk:note "See obstruction flow in Pool Covers")
              (chk:note "No obstructions - do nothing")
            )
          )
        )
        v))
      (cons 'obst '(lambda () (chk:obstruction)))
      (cons nil '(lambda ()
        (setq v (chk:yesno "Raised?" T))
        (if (not (eq v 'CHK-BACK)) (setq raised v))
        v))
      (cons 'raised '(lambda ()
        (chk:confirm "the height of the spa (state it on the drawing)" T)))
      (cons 'raised '(lambda ()
        (setq v (chk:yesno "Attaching to pool cover?" T))
        (if (not (eq v 'CHK-BACK))
          (progn
            (setq attach v)
            (if attach (chk:note "Note: loose clips will attach to the pool cover"))
          )
        )
        v))
      (cons '(and raised (not attach)) '(lambda ()
        (setq v (chk:yesno "Drum style cover?" T))
        (if (not (eq v 'CHK-BACK))
          (if v
            (chk:note "Add drum style note")
            (chk:note "Spa might need extension straps")
          )
        )
        v))
      (cons '(not raised) '(lambda ()
        (setq v (chk:yesno "Joined wall for spa and pool?" T))
        (if (and (not (eq v 'CHK-BACK)) v) (chk:note "Pad the wall"))
        v))
    )
    T
  )
)

;; Hard cover spillway sub-flow
(defun chk:spa-hard-spillway (/ v)
  (setq v (chk:yesno "Spillway?" T))
  (cond
    ((eq v 'CHK-BACK) v)
    (v
     (chk:note "Go through gap filler and custom block rules to determine")
     (chk:note "Draw the Gap Filler / Custom Block on the spa cover on the cover layer")
     (chk:note "Make sure the inside and outside spillway dims are shown")
     (chk:note (strcat "Make sure the spillway is shown on the bottom or right hand "
                       "side; dimensions and notes go on the dimension itself"))
     (chk:note (strcat "If using a custom block, draw a 3D custom block detail off "
                       "to the side dimensioning the custom block showing LxWxH"))
     v)
    (T (chk:note "No need to show anything for the spillway") v)
  )
)

(defun chk:spa-hard (/ v)
  (chk:seq
    (list
      (cons nil '(lambda ()
        (setq v (chk:ask "Spa type" "AboveGround InGround" T))
        (if (= v "InGround")
          (progn
            (chk:note "Heavy Duty Bottom / Hold Down Kit")
            (chk:note "6\" overlap might be required")
            (chk:note "Show overlap dimension")
            (chk:note "Show water's edge / overlap if given")
          )
        )
        v))
      (cons nil '(lambda () (chk:confirm "pieces are no more than 48\"" T)))
      (cons nil '(lambda () (chk:confirm "Hinges" T)))
      (cons nil '(lambda () (chk:confirm "Spa Cover Size" T)))
      (cons nil '(lambda () (chk:spa-hard-spillway)))
    )
    T
  )
)

(defun chk:spa-thermolight (/ v)
  (setq v (chk:confirm "Cover Size is for water's edge" T))
  (if (not (eq v 'CHK-BACK))
    (progn
      (chk:note "All Velcro hinges - pieces can be up to 53\" but are typically at most 48\"")
      (chk:note "No need to worry about spillways")
      (chk:note "Cover size dimensions should be shown")
    )
  )
  v
)

(defun chk:spa-cover (/ kind v)
  (chk:seq
    (list
      (cons nil '(lambda ()
        (setq v (chk:ask "Spa cover type" "SafetyCover HardCover ThermoLight" T))
        (if (not (eq v 'CHK-BACK)) (setq kind v))
        v))
      (cons nil '(lambda ()
        (cond
          ((= kind "SafetyCover") (chk:spa-safety))
          ((= kind "HardCover")   (chk:spa-hard))
          (T                      (chk:spa-thermolight))
        )))
    )
    T
  )
)

;;; ------------------------------------------------------------------
;;; Main command
;;; ------------------------------------------------------------------

(defun c:CCPRECHECK (/ *error* product v)
  ;; a walker: it changes no setting and opens no undo group, so the
  ;; handler's whole job is to keep a cancel from printing a raw
  ;; AutoLISP message at the user (STANDARDS section 5)
  (defun *error* (msg)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
        (princ (strcat "\nCCPRECHECK error: " msg)))
    (princ))

  (setq *chk:log* nil product nil)
  (princ "\n--- Tech Flow Chart checklist ---")
  (princ "\n(after the first question, Back re-asks the previous one)")
  (chk:seq
    (list
      (cons nil '(lambda ()
        (setq v (chk:ask "Product type" "Liner PoolCover SpaCover" nil))
        (setq product v)
        v))
      (cons nil '(lambda ()
        (cond
          ((= product "Liner")     (chk:liner))
          ((= product "PoolCover") (chk:pool-cover))
          (T                       (chk:spa-cover))
        )))
    )
    nil
  )
  ;; Summary of everything answered / noted along the way
  (princ "\n\n--- Checklist summary ---")
  (foreach line *chk:log*
    (princ (strcat "\n  " line))
  )
  (princ "\n--- End of checklist ---\n")
  (princ)
)

(defun c:CCPRECHECKVER ()
  (princ (strcat "\nCCPRECHECK " *ccprecheck-version*))
  (princ))

(princ (strcat "\nCCPRECHECK " *ccprecheck-version*
               " loaded. Type CCPRECHECK to run the tech flow chart checklist."))
(princ)
