;;; ======================================================================
;;; PERPMARKSTAMP.lsp  --  PERPMARK's round, with the distance stamped
;;;                        beside every mark as it is drawn
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  PERPMARKSTAMP     PERPMARK, with a stamp after every mark
;;;            PERPMARKSTAMPVER  print the loaded version
;;; ======================================================================
;;;
;;; What it is for
;;;   PERPMARK marks what the tape read at a survey point -- a circle of
;;;   that radius and a line of that length square off the wall -- and
;;;   only when the round is joined into a polyline does each line
;;;   become a dimension that says the number.  A round that is NOT
;;;   joined (a bench sketched in for a look, a gutter noted for the
;;;   next drafter, the marks of a step kept as marks) leaves a circle
;;;   and a line at every point and no number anywhere, so the drafter
;;;   turned to DIMSTAMP and stamped each distance by hand, reading the
;;;   sheet a second time to do it.
;;;
;;;   PERPMARKSTAMP is PERPMARK with that stamp folded in.  Every
;;;   question is PERPMARK's, asked in PERPMARK's words, and after each
;;;   mark is drawn there is one more:
;;;
;;;     Click where to stamp 3'-8" for Pt.17 [Skip/Back] <at the mark's end>:
;;;
;;;   Enter stamps the distance at the far end of the mark, where the
;;;   tape reached; a click stamps it there instead; Skip stamps
;;;   nothing for this mark; Back takes the mark away again, exactly as
;;;   Back at the next point prompt would.  The stamp is DIMSTAMP's: an
;;;   MTEXT on the TEXT layer in the Attributes style, 6" high, attached
;;;   top left, ByLayer, upright in the current UCS, its fraction
;;;   stacked the way the shop's own dimension text stacks one.  It is
;;;   spelled the way the distance was TYPED -- 44 1/2" for one typed
;;;   in inches, 3'-8 1/2" for one typed in feet -- since that is what
;;;   the ruler beside the distance prompt was showing.
;;;
;;;   It does not copy PERPMARK.  PERPMARK carries a hook for exactly
;;;   this -- pm:run-hooked runs the round with a function called after
;;;   every mark -- and this file is that function and the command that
;;;   installs it.  So it needs PERPMARK v1.13 or later loaded:
;;;   APPLOADed alone without it, it says so and stops; in the LAZPASS
;;;   build the two load together.
;;;
;;; What rides on the mark
;;;   A stamp belongs to the mark it was made for.  Back at the next
;;;   point prompt takes the last mark AND its stamp away; naming a
;;;   point a second time replaces the mark and the stamp both; a Skip
;;;   leaves a mark with no stamp, which is a plain PERPMARK mark.  When
;;;   the round is joined into a polyline the circles go and the lines
;;;   become dimensions, as in PERPMARK, and the stamps STAY: they are
;;;   drawing text, not working marks, and the drafter who placed them
;;;   meant them to be read.  A round answered No to the polyline keeps
;;;   its marks and its stamps together.
;;;
;;;   One undo group, PERPMARK's: a single U takes the whole round back,
;;;   stamps included.  Esc anywhere -- the stamp prompt included -- is
;;;   PERPMARK's Esc: its settings back, its ruler down, its group
;;;   closed, and the failure reported under PERPMARKSTAMP, whose
;;;   LAZDIAG run PERPMARK's joined, with every answer from both.
;;;
;;; What it does not do
;;;   * It stamps the DISTANCE and nothing else -- not the point number,
;;;     not a letter.  DIMSTAMP is there for a label.
;;;   * It does not move a stamp when its mark is replaced: a re-mark
;;;     asks again, and the new answer is where the new stamp goes.
;;;   * It does not read a stamp back.  The dimensions PERPMARK draws
;;;     at the join are still the measurement of record; a stamp is the
;;;     number written beside it.
;;;
;;; License: GPL-3.0-or-later
;;; ======================================================================

(vl-load-com)

;; Version banner: tools/release_lisp.py reads it to stamp the dated
;; REV twin in releases/ (vN.M -> _MMDDYY_REVNM).
(setq *perpmarkstamp-version* "v1.0")

;;; -------------------- tunables ----------------------------------------
;;; What a stamp IS: the MTEXT properties the shop's dimension text
;;; carries, the same knobs DIMSTAMP has under its own prefix.  Change
;;; one and every later stamp takes it; change DIMSTAMP's to match, or
;;; a stamp placed here and one placed there stop looking alike.

(setq pms:*layer* "TEXT")           ; layer the stamped MTEXT lands on.
                                    ; Created when the drawing lacks it;
                                    ; thawed, unlocked and switched on
                                    ; when it is there but unusable
(setq pms:*layer-color* 7)          ; ACI colour that layer is CREATED
                                    ; with -- 7 is AutoCAD's own
                                    ; black-on-white/white-on-black
                                    ; swap.  A number and never 'auto: a
                                    ; layer record outlives the command
                                    ; and colours everything ByLayer on
                                    ; it for whoever opens the drawing
                                    ; next.  The stamp itself is ByLayer
(setq pms:*style* "Attributes")     ; text style the stamp is written
                                    ; in.  A drawing without it gets a
                                    ; plain variable-height style of
                                    ; that name made, and is told so
(setq pms:*text-hgt* 6.0)           ; MTEXT height of a stamp
(setq pms:*text-width* 0.0)         ; its defined (wrap) width; 0 is no
                                    ; wrap at all, so a distance can
                                    ; never break across two lines
(setq pms:*line-space* 1.0)         ; line space factor, at the "at
                                    ; least" spacing style

;;; ----------------------------------------------------------------------
;;;  Library copies
;;;  Copied from CALOFIN-LIB.lsp under this file's own prefix, so the
;;;  standalone file loads alone -- see STANDARDS.md section 4.  The
;;;  mirror swaps them back, so each must be the library's text.
;;; ----------------------------------------------------------------------

;; Create the output layer, or - when it already exists - make sure it
;; is on, thawed and unlocked.  Without this a successful run onto a
;; frozen or switched-off layer looks like the command did nothing.
(defun pms:ensure-layer (name color / rec ed flags col fixed)
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

;; INCHES to the nearest eighth, as an integer count of eighths -- the
;; unit the ruler is built in.
(defun pms:len-eighths (inches)
  (fix (+ 0.5 (* 8.0 inches))))

;; Spell TOTAL-EIGHTHS out as text, in the HASFEET family.  STACKED nil
;; is the PLAIN spelling ("44 1/2\"", what the command line says);
;; STACKED T is the DRAWN one, the fraction stacked through AutoCAD's
;; \S code at the size of the text around it, for a ruler label and
;; nothing else.
(defun pms:spell-len (total-eighths hasfeet stacked / feet remain whole f8
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

;;; ----------------------------------------------------------------------
;;;  The stamp
;;;  DIMSTAMP's MTEXT, written from a number rather than from typed
;;;  text: the same layer, style, height, attachment and turn.
;;; ----------------------------------------------------------------------

;; The text style the stamps are written in.  A drawing that already
;; has it keeps its own font and settings, untouched; one that does not
;; gets a plain variable-height style of that name, and is told -- an
;; entmake naming a style the drawing has not got is refused outright,
;; so the alternative is a stamp that silently draws nothing.
(defun pms:ensure-style (name)
  (if (not (tblsearch "STYLE" name))
    (progn
      (entmakex (list '(0 . "STYLE") '(100 . "AcDbSymbolTableRecord")
                      '(100 . "AcDbTextStyleTableRecord")
                      (cons 2 name) '(70 . 0)
                      '(40 . 0.0)            ; variable height: the
                                             ; entity's own governs
                      '(41 . 1.0) '(50 . 0.0) '(71 . 0) '(42 . 2.5)
                      '(3 . "txt") '(4 . "")))
      (princ (strcat "\nPERPMARKSTAMP: text style " name
                     " was not in this drawing - a plain one was made"
                     " so the stamps have a style to carry."))))
  name)

;; How far the current UCS is turned from the world X axis, so text
;; reads along the UCS the drafter is drawing in.  Taken off the UCS X
;; axis moved into the world -- not off UCSXDIR run back into the UCS,
;; which is (1 0 0) there however far the UCS is turned, so it would
;; always answer zero.  0 in the world UCS.
(defun pms:ucsang ( / v)
  (setq v (trans '(1.0 0.0 0.0) 1 0 T))
  (atan (cadr v) (car v)))

;; One MTEXT reading STR at the WORLD point PT, written the way the
;; shop's dimension text is: the stamp style, unwrapped, upright in the
;; UCS, attached top left at PT, ByLayer.  PT is WCS because both
;; places a stamp can go arrive that way -- the mark's far end from
;; PERPMARK's own geometry, a click through trans -- and entmake reads
;; group 10 as WORLD.  Returns the ename.
(defun pms:mtext (pt str)
  (entmakex
    (list '(0 . "MTEXT") '(100 . "AcDbEntity") (cons 8 pms:*layer*)
          '(100 . "AcDbMText")
          (cons 10 (list (car pt) (cadr pt) 0.0))
          (cons 40 pms:*text-hgt*)
          (cons 41 pms:*text-width*)    ; 0 = no wrap
          '(71 . 1)                     ; attachment: top left
          '(72 . 5)                     ; direction: by style
          (cons 1 str)
          (cons 7 pms:*style*)
          (cons 50 (pms:ucsang))        ; upright in the UCS
          '(73 . 1)                     ; line spacing: at least
          (cons 44 pms:*line-space*))))

;; The two spellings of DIST inches in the HASFEET family: PLAIN is
;; what the prompt says (44 1/2"), DRAWN is what reaches the MTEXT,
;; the fraction stacked at the size of the text around it.  Nothing
;; but the drawn spelling is ever stamped, and nothing but the plain
;; one is ever printed.
(defun pms:plain (dist hasfeet)
  (pms:spell-len (pms:len-eighths dist) hasfeet nil))

(defun pms:drawn (dist hasfeet)
  (pms:spell-len (pms:len-eighths dist) hasfeet T))

;; Stamp DIST at the WORLD point PT -- the drawing content this whole
;; file exists for.  The layer and the style are made good first, so a
;; stamp can never be refused for want of either.  Returns the ename.
(defun pms:stamp (pt dist hasfeet)
  (pms:ensure-layer pms:*layer* pms:*layer-color*)
  (pms:ensure-style pms:*style*)
  (pms:mtext pt (pms:drawn dist hasfeet)))

;;; ----------------------------------------------------------------------
;;;  The hook
;;; ----------------------------------------------------------------------

;; What PERPMARK calls after every mark, through pm:run-hooked: DIST in
;; inches, OFFS the far end of the mark as a WCS (x y), NAME the point
;; as the prompts spell it, HASFEET T when the distance was typed in
;; feet.  One question, and every way of answering it: Enter stamps at
;; OFFS, a click stamps there, Skip stamps nothing, Back hands PM-BACK
;; back and PERPMARK takes the mark away.  Returns what it drew as a
;; list -- one MTEXT -- or nil, or PM-BACK; PERPMARK erases the list
;; with the mark on Back and on a re-mark.
;;
;; The sentinel is PERPMARK's on purpose: the value is handed to
;; PERPMARK, so it has to be PERPMARK's word for Back, and it travels
;; to the library's with the twin exactly as PERPMARK's own does.
(defun pms:after-mark (dist offs name hasfeet / txt pk out)
  (setq txt (pms:plain dist hasfeet) out nil)
  (initget "Skip Back Undo")
  (setq pk (getpoint (strcat "\nClick where to stamp " txt " for " name
                             " [Skip/Back] <at the mark's end>: ")))
  (if lzd:ask (lzd:ask (getvar "LASTPROMPT") pk) pk)
  (cond
    ((null pk)
     (setq out (list (pms:stamp offs dist hasfeet)))
     (princ (strcat "\n  " txt " stamped at the end of the mark.")))
    ((and (= (type pk) 'STR) (member pk '("Back" "Undo")))
     (setq out 'PM-BACK))
    ((= (type pk) 'STR)                     ; Skip
     (princ (strcat "\n  " name " not stamped.")))
    (t
     (setq out (list (pms:stamp (trans pk 1 0) dist hasfeet)))
     (princ (strcat "\n  " txt " stamped."))))
  out)

;;; ----------------------------------------------------------------------
;;;  The command
;;; ----------------------------------------------------------------------

(defun c:PERPMARKSTAMP (/ *error*)
  ;; Nothing of this command's own to put back: the settings, the
  ;; ruler and the undo group are PERPMARK's, and an Esc inside the run
  ;; -- the stamp prompt included -- reaches PERPMARK's handler, which
  ;; puts them back and reports under this command, whose LAZDIAG run
  ;; PERPMARK's joined.  This handler is for a failure before or after
  ;; the hand-over.
  (defun *error* (msg)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nPERPMARKSTAMP error: " msg)))
    (if lzd:report (lzd:report "PERPMARKSTAMP" *perpmarkstamp-version* msg))
    (princ))

  (if lzd:begin (lzd:begin "PERPMARKSTAMP" *perpmarkstamp-version*))
  (cond
    ;; pm:run-hooked arrived with PERPMARK v1.13: an older PERPMARK is
    ;; loaded but cannot take the hook, and is told apart from none
    ((not pm:run-hooked)
     (princ (strcat "\nPERPMARKSTAMP: PERPMARK v1.13 or later is not"
                    " loaded in this drawing - APPLOAD PERPMARK.lsp (or"
                    " the whole LAZPASS.lsp build, which has both) and"
                    " run PERPMARKSTAMP again.")))
    (t
     (princ (strcat "\nPERPMARKSTAMP " *perpmarkstamp-version*
                    " - PERPMARK's round, with the distance stamped after"
                    " every mark: Enter puts it at the mark's end, a click"
                    " puts it there, Skip leaves it off."))
     (pm:run-hooked 'pms:after-mark)))
  (if lzd:end (lzd:end "PERPMARKSTAMP"))
  (princ))

(defun c:PERPMARKSTAMPVER ()
  (princ (strcat "\nPERPMARKSTAMP " *perpmarkstamp-version*))
  (princ))

;; -------------------- self tests ---------------------------------------
;; What LAZDIAG runs on the drafter's machine after this tool fails, and
;; writes into the report: the tool's own helpers on inputs whose answers
;; are KNOWN, so the report says whether the arithmetic was sound where
;; it ran.  (label expression expected) passes when the value is equal
;; to expected (to 1e-6); (label expression) passes when it is not nil,
;; and the value is written down either way.  Nothing here may prompt,
;; draw or (command): it is evaluated from inside *error*.
;; tests/test_selftests.py runs every entry in the VM at both tiers.
(defun pms:selftests ()
  (list
    (list "len-eighths rounds 44.5 inches to 356 eighths"
          '(pms:len-eighths 44.5)  356)
    (list "plain spelling of 44.5 typed in inches is 44 1/2 with the inch mark"
          '(pms:plain 44.5 nil)  "44 1/2\"")
    (list "plain spelling of 44.5 typed in feet is 3'-8 1/2"
          '(pms:plain 44.5 T)  "3'-8 1/2\"")
    (list "drawn spelling stacks the fraction at the text's own height, centred"
          '(pms:drawn 44.5 nil)  "\\A1;44{\\H1.0000x;\\S1/2;}\"")
    (list "a whole number of inches is drawn with no stack code at all"
          '(pms:drawn 36.0 T)  "3'-0\"")))

(foreach c '("PERPMARKSTAMP")
  (setq *calofin-selftests*
        (cons (cons c 'pms:selftests) *calofin-selftests*)))

;; Quiet inside the whole build: LAZPASS.lsp and CALOFIN-LOADER.lsp set
;; the flag while they load their members.  APPLOADed alone the flag
;; is nil and this prints, which is the one time somebody wants to be
;; told.
(if (not *calofin-quiet*)
  (princ (strcat "\nPERPMARKSTAMP " *perpmarkstamp-version*
                 " loaded.  Type PERPMARKSTAMP to run (needs PERPMARK"
                 " v1.13 or later loaded too).")))
(princ)
