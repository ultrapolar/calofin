;;; ======================================================================
;;; DRONOTE.lsp  --  place a canned drone-photo review note
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  DRONOTE       place one of three canned review notes
;;;            DRONOTEVER    print the loaded version
;;; ----------------------------------------------------------------------
;;; DRONOTE asks which of three notes you want -- the ones that come up
;;; over and over reviewing a job built off a drone photo -- then lets
;;; you click as many spots as you like to drop that same note, Enter
;;; when done:
;;;
;;;   Board    How far is the diving board base from water's edge?
;;;   Anchors  Some anchors are not visible in the drone photo provided.
;;;   Slide    Please provide a detailed sketch to locate slide base
;;;            for proper cover treatment.
;;;
;;; Each note is an MTEXT dropped at the picked point, on the
;;; dn:*layer* layer.  Back at the point prompt un-places the last one
;;; instead of ending the run, so a bad click costs one Back rather
;;; than a manual erase; Back with nothing placed yet steps back to the
;;; note choice instead.  Run the command again to place a different
;;; note.
;;;
;;; Every knob -- layer and its colour, text height and wrap width -- is
;;; in the configuration block right below.
;;;
;;; Versioning: see tools/release_lisp.py at the repo root.  It reads
;;; *dronote-version* below and stamps a dated, REV-numbered twin of
;;; this file into releases/.
;;; ======================================================================

;;; -------------------- version ---------------------------------------
(setq *dronote-version* "v1.0")   ; announced on load; release_lisp.py
                                  ; reads this banner and stamps the
                                  ; dated twin in releases/ from it

;;; -------------------- tunables --------------------------------------
;;; Every knob the routine has, in one place, so nothing below this
;;; block needs touching to adapt it.  Change a value here, or (setq ...)
;;; it after loading from a startup file.  Distances are DRAWING UNITS -
;;; inches in this shop's architectural drawings.

(setq dn:*layer* "NOTES")           ; layer every note lands on - created
                                    ; when the drawing lacks it; thawed,
                                    ; unlocked and switched on when it
                                    ; is there but unusable
(setq dn:*layer-color* 2)           ; ACI colour that layer is CREATED
                                    ; with (2 = yellow).  A layer already
                                    ; in the drawing keeps its own
(setq dn:*text-hgt* 6.0)            ; MTEXT height of a placed note
(setq dn:*text-width* 96.0)         ; MTEXT reference width (8'), so a
                                    ; long note wraps instead of running
                                    ; clear across the sheet

;;; -------------------- the three notes ---------------------------------
;;; dn:*kws* is BOTH the initget keyword list and the bracket text
;;; (STANDARDS section 1 rule 1) - keep it in step with dn:*notes*'s keys.
(setq dn:*kws* "Board Anchors Slide")
(setq dn:*notes*
  (list
    (cons "Board"
          "How far is the diving board base from water's edge?")
    (cons "Anchors"
          "Some anchors are not visible in the drone photo provided.")
    (cons "Slide"
          (strcat "Please provide a detailed sketch to locate slide"
                  " base for proper cover treatment."))))

;;; -------------------- helpers -----------------------------------------

;; Create the output layer, or make sure it is on, thawed, unlocked.
(defun dn:ensure-layer (name colour / rec ed flags col fixed)
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
          (princ (strcat "\nDRONOTE: layer " name
                         " was off, frozen or locked - restored so the"
                         " result is visible.")))))))

;; entmake an MTEXT at INS reading STR, splitting into 250-char DXF
;; chunks - MTEXT carries at most 250 characters in group 1, so a note
;; lengthened past that would otherwise lose everything past the first
;; chunk.  Returns the new ename.
(defun dn:mtext (ins str / dxf)
  (setq dxf (list '(0 . "MTEXT") '(100 . "AcDbEntity")
                  (cons 8 dn:*layer*) '(100 . "AcDbMText")
                  (cons 10 ins) (cons 40 dn:*text-hgt*)
                  (cons 41 dn:*text-width*) '(71 . 1)))   ; top-left
  (while (> (strlen str) 250)
    (setq dxf (append dxf (list (cons 3 (substr str 1 250))))
          str (substr str 251)))
  (entmakex (append dxf (list (cons 1 str)))))

;;; -------------------- the command --------------------------------------
;; NOTE: no local here may be named after a function this routine
;; calls - an AutoLISP local SHADOWS the function of the same name for
;; the whole call (the BPCALLOUT v1.0 lesson).
(defun c:DRONOTE ( / *error* undo-open stage note txt pt placed count)
  (defun *error* (msg)
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (setq undo-open nil)
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nDRONOTE error: " msg)))
    (if lzd:report (lzd:report "DRONOTE" *dronote-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "DRONOTE" *dronote-version*))
  ;; only when undo is recording - _Begin in a drawing with UNDO off
  ;; (bit 1 of UNDOCTL clear) errors out of the command
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn
      (command "_.UNDO" "_Begin")
      (setq undo-open T)))

  (princ (strcat "\nDRONOTE " *dronote-version*))
  (setq stage 'NOTE placed nil count 0)
  (while (not (eq stage 'DONE))
    (cond
      ((eq stage 'NOTE)
       (initget 1 dn:*kws*)
       (setq note (getkword (strcat "\nWhich note? ["
                                    (vl-string-translate " " "/" dn:*kws*)
                                    "]: ")))
       (if lzd:ask (lzd:ask (getvar "LASTPROMPT") note) note)
       (setq txt (cdr (assoc note dn:*notes*)))
       (princ (strcat "\n  \"" txt "\""))
       (setq stage 'PLACE))
      (T                                   ; stage = PLACE
       (initget 128)
       (setq pt (getpoint (strcat "\nPick a point for the note (Enter"
                                  " when done) [Back]: ")))
       (if lzd:ask (lzd:ask (getvar "LASTPROMPT") pt) pt)
       (cond
         ((null pt) (setq stage 'DONE))
         ((and (= (type pt) 'STR)
               (member (strcase pt) '("B" "BACK" "U" "UNDO")))
          (if placed
            (progn
              (if (and (caar placed) (entget (caar placed)))
                (entdel (caar placed)))
              (setq placed (cdr placed)
                    count  (1- count))
              (princ "\n  Last note removed."))
            (progn
              (princ "\n  Back to the note choice.")
              (setq stage 'NOTE))))
         (T
          (dn:ensure-layer dn:*layer* dn:*layer-color*)
          (setq placed (cons (cons (dn:mtext (list (car pt) (cadr pt) 0.0)
                                             txt)
                                   txt)
                             placed)
                count  (1+ count))
          (princ "\n  Note placed."))))))

  (if undo-open
    (progn
      (command "_.UNDO" "_End")
      (setq undo-open nil)))
  (princ (strcat "\nDRONOTE: " (itoa count) " note"
                 (if (= count 1) "" "s")
                 " placed on layer " dn:*layer* "."))
  (if lzd:end (lzd:end "DRONOTE"))
  (princ))

(defun c:DRONOTEVER ()
  (princ (strcat "\nDRONOTE " *dronote-version*))
  (princ))

;; Quiet inside the whole build: LAZPASS.lsp and
;; CALOFIN-LOADER.lsp set the flag while they load their members,
;; because one file's greeting is a greeting and sixty-three of
;; them is a wall the drafter scrolls past in every drawing they
;; open.  APPLOADed alone the flag is nil and this prints, which
;; is the one time somebody wants to be told.  CALVER reports the
;; whole roster whenever it is asked.
(if (not *calofin-quiet*)
  (princ (strcat "\nDRONOTE " *dronote-version*
                 " loaded. Command: DRONOTE (place a canned drone-photo"
                 " review note).")))
(princ)
