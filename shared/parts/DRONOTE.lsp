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
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;
;;;   Board    How far is the diving board base from water's edge?
;;;   Anchors  Some anchors are not visible in the drone photo provided.
;;;   Slide    Please provide a detailed sketch to locate slide base
;;;            for proper cover treatment.
;;;
;;; Each note is one MTEXT, dropped with its TOP LEFT CORNER at the
;;; picked point and written the way the shop's own review notes are --
;;; the standing header first, the note bulleted under it:
;;;
;;;   *All listed issues must be resolved to proceed with design*
;;;   - Some anchors are not visible in the drone photo provided.
;;;
;;; -- on the TEXT layer, in the Attributes style at 9.5, wrapped at the
;;; width those note blocks carry.
;;;
;;; Back at the point prompt un-places the last one instead of ending
;;; the run, so a bad click costs one Back rather than a manual erase;
;;; Back with nothing placed yet steps back to the note choice instead.
;;; Run the command again to place a different note.
;;;
;;; Every knob -- the header and the bullet, the layer and its colour,
;;; the text style and its font, text height, wrap width and line
;;; spacing -- is in the configuration block right below.
;;;
;;; Versioning: see tools/release_lisp.py at the repo root.  It reads
;;; *dronote-version* below and stamps a dated, REV-numbered twin of
;;; this file into releases/.
;;; ======================================================================

;;; -------------------- version ---------------------------------------
(setq *dronote-version* "v1.2")   ; announced on load; release_lisp.py
                                  ; reads this banner and stamps the
                                  ; dated twin in releases/ from it

;;; -------------------- tunables --------------------------------------
;;; Every knob the routine has, in one place, so nothing below this
;;; block needs touching to adapt it.  Change a value here, or (setq ...)
;;; it after loading from a startup file.  Distances are DRAWING UNITS -
;;; inches in this shop's architectural drawings.

(setq dn:*layer* "TEXT")            ; layer every note lands on - the
                                    ; shop's own text layer, the one its
                                    ; note blocks and DIMSTAMP's stamps
                                    ; are already on.  Created when the
                                    ; drawing lacks it; thawed, unlocked
                                    ; and switched on when it is there
                                    ; but unusable
(setq dn:*layer-color* 4)           ; ACI colour that layer is CREATED
                                    ; with (4 = cyan, what the office
                                    ; template carries).  A layer already
                                    ; in the drawing keeps its own, and
                                    ; the note itself is ByLayer either
                                    ; way
(setq dn:*style* "Attributes")      ; text style a note is written in -
                                    ; the shop's own.  A drawing without
                                    ; it gets a variable-height style of
                                    ; that name made from the font below
                                    ; and is told so; one that has it
                                    ; keeps its own font and height
(setq dn:*style-font* "arialbd.ttf")
                                    ; font a style MADE here is
                                    ; built on; one already in the
                                    ; drawing keeps its own
(setq dn:*text-hgt* 9.5)            ; MTEXT height of a placed note
(setq dn:*text-width* 440.1875)     ; MTEXT reference width, so a long
                                    ; note wraps instead of running clear
                                    ; across the sheet - the width the
                                    ; shop's own note blocks carry
(setq dn:*line-space* 1.0)          ; line space factor, at the "at
                                    ; least" spacing style: what sets the
                                    ; note under its header
(setq dn:*header* "*All listed issues must be resolved to proceed with design*")
                                    ; the standing first line of every
                                    ; note, the shop's own wording.  ""
                                    ; writes the note with no header over
                                    ; it
(setq dn:*bullet* "- ")             ; what the note itself is prefixed
                                    ; with under that header

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

;; Make sure the style a note is written in is there to carry.  A
;; drawing that has it keeps its own font and height - the note asks
;; for nothing but the name; one that has not gets a plain
;; variable-height style of that name, built on FONT, so the note is
;; not silently written in whatever STANDARD happens to be.
(defun dn:ensure-style (name font)
  (if (not (tblsearch "STYLE" name))
    (progn
      (entmakex (list '(0 . "STYLE") '(100 . "AcDbSymbolTableRecord")
                      '(100 . "AcDbTextStyleTableRecord")
                      (cons 2 name) '(70 . 0)
                      '(40 . 0.0)            ; variable height: the
                                             ; entity's own governs
                      '(41 . 1.0) '(50 . 0.0) '(71 . 0) '(42 . 2.5)
                      (cons 3 font) '(4 . "")))
      (princ (strcat "\nDRONOTE: text style " name
                     " was not in this drawing - a plain one was made"
                     " so the notes have a style to carry."))))
  name)

;; What one note READS as: the standing header, then the note itself
;; bulleted on the line under it.  \P is MTEXT's paragraph break, and
;; dn:*line-space* is what sets the second line under the first.  A
;; dn:*header* emptied to "" leaves the bullet line on its own.
(defun dn:written (txt)
  (if (and dn:*header* (> (strlen dn:*header*) 0))
    (strcat dn:*header* "\\P" dn:*bullet* txt)
    (strcat dn:*bullet* txt)))

;; entmake an MTEXT at INS reading STR, in the properties the shop's own
;; review notes carry: attached TOP LEFT at the point, dn:*style* at
;; dn:*text-hgt*, wrapped at dn:*text-width*, upright, its lines spaced
;; the "at least" way, and ByLayer on dn:*layer*.  STR is split into
;; 250-char DXF chunks - MTEXT carries at most 250 characters in group
;; 1, and the header takes a fixed bite out of that, so a note
;; lengthened past it would otherwise lose everything past the first
;; chunk.  Returns the new ename.
(defun dn:mtext (ins str / dxf)
  (setq dxf (list '(0 . "MTEXT") '(100 . "AcDbEntity")
                  (cons 8 dn:*layer*) '(100 . "AcDbMText")
                  (cons 10 ins) (cons 40 dn:*text-hgt*)
                  (cons 41 dn:*text-width*)
                  '(71 . 1)                  ; attachment: top left
                  '(72 . 5)))                ; direction: by style
  (while (> (strlen str) 250)
    (setq dxf (append dxf (list (cons 3 (substr str 1 250))))
          str (substr str 251)))
  (entmakex (append dxf
                    (list (cons 1 str)
                          (cons 7 dn:*style*)
                          '(50 . 0.0)        ; rotation
                          '(73 . 1)          ; line spacing: at least
                          (cons 44 dn:*line-space*)))))

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
         ;; initget 128 lets ANY typed word through, not just Back: a
         ;; word that is not one of ours is re-asked, never handed to
         ;; (car pt) -- "done" used to end the command in an error
         ((= (type pt) 'STR)
          (princ (strcat "\n  \"" pt "\" is not a point - pick one, press"
                         " Enter when done, or type Back.")))
         (T
          (cal:ensure-layer dn:*layer* dn:*layer-color*)
          (dn:ensure-style dn:*style* dn:*style-font*)
          (setq placed (cons (cons (dn:mtext (list (car pt) (cadr pt) 0.0)
                                             (dn:written txt))
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
