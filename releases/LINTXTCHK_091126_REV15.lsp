;;; ==========================================================================
;;; LINTXTCHK.lsp  --  Liner Text Checklist
;;; --------------------------------------------------------------------------
;;; Places the vinyl pool-liner drawing checklist into the current drawing as
;;; a column of individual TEXT entities (one entity per line) starting at a
;;; point the user picks.  The text height, the line spacing, the indent
;;; and the checklist itself are the tunables below.  Sub-items are
;;; indented under their parent.
;;;
;;; Usage:  APPLOAD this file (or add it to your startup suite), then type
;;;         LINTXTCHK and pick the top-left point for the checklist.
;;; ==========================================================================

(setq *lintxtchk-version* "v1.5")   ; announced on load; release_lisp.py
                                       ; stamps the dated twin in releases/

;;; ======================================================================
;;;  TUNABLES -- everything about this checklist that someone might want
;;;  to change lives in this block, and nowhere else in the file.
;;;
;;;  How to change one: edit the value, save, and APPLOAD the file
;;;  again.  To try a value for one session only, type the setq at the
;;;  command line -- e.g. (setq ltc:*height* 6.0) -- because every knob
;;;  is read when the command runs, not when the file loads.  (They
;;;  used to be locals of the command, which meant neither route
;;;  worked: changing one needed a trip inside the defun, and a setq
;;;  typed at the command line was overwritten the moment the command
;;;  started.)
;;; ----------------------------------------------------------------------

;; -- how the column is laid out ----------------------------------------

;; Text height, in drawing units (1 unit = 1 inch on the shop's
;; sheets).  The next two are multiples of it, so changing this alone
;; rescales the whole block and keeps its proportions.
(setq ltc:*height*   12.0)

;; Vertical distance between lines, and the horizontal indent per
;; sub-level, both as multiples of the text height.  1.6 leaves a
;; comfortable gap; under about 1.2 the lines start to touch.
(setq ltc:*spacing*  1.6)
(setq ltc:*indent*   1.5)

;; What every line is prefixed with.  "" gives a plain column,
;; "[ ] " gives boxes to tick.
(setq ltc:*bullet*   "- ")

;; -- the checklist itself ------------------------------------------------

;; Each entry is (indent-level . "line text").  Level 0 is a main item,
;; 1 a sub-item indented under the one above it; a deeper level simply
;; indents further.  Inner double quotes and inch marks are escaped
;; with a backslash.
;;
;; This is the shop's checklist, so it is content rather than a
;; setting -- but it sits here, at the top, because editing it is why
;; most people open this file.  Add, remove or reword a line and the
;; count in the done message follows on its own.
(setq ltc:*items*
  (list
    (cons 0 "Read all WSN (White Screen Notes), Notes from Merlin, and Customer Info")
    (cons 1 "Does this job actually require a Tech drawing?")
    (cons 0 "Verify Finished Wall Ht & Pool Depth")
    (cons 1 "Finished Wall Ht should be a single value, or \"Varies\" if needed")
    (cons 0 "Place liner pattern block (GLP) - Delete \"Not Supplied\" text")
    (cons 0 "Verify the type of pool bead, or overlap for AG, etc")
    (cons 0 "Pool perimeter & overall dims")
    (cons 0 "Verify orientation: Shallow end to the RIGHT of page")
    (cons 0 "Report ALL cross dimensions provided by customer")
    (cons 0 "Pool corners with dimensions")
    (cons 1 "Look out special mfgrs like Esther Williams (3x3, 5x5) or Foxx (37\" Deep)")
    (cons 0 "Look for special bottom conditions:")
    (cons 1 "Does the shallow end have a Cove?")
    (cons 1 "Does the pool have a Safety Ledge?")
    (cons 1 "Did the customer provide various depths for the bottom?")
    (cons 1 "Does the pool require a side view?")
    (cons 0 "Are hopper corners radius?")
    (cons 0 "Did you draw trowel lines accurately?")
    (cons 0 "Are steps / bench Fiberglass?")
    (cons 1 "Place FGS note or draw step outline if dimensions were provided")
    (cons 1 "Is the step Straight or Radius? Ask if not given")
    (cons 0 "Are steps / bench Vinyl-covered?")
    (cons 1 "Verify step corner type & dimensions")
    (cons 1 "Place Step Attachment block - is the attachment type provided?")
    (cons 1 "Place side views for all steps and benches")
    (cons 0 "Did you scale the titleblock? REDVIEW!")
  )
)
;;; ----------------------------------------------------------------------
;;;  END TUNABLES.  LINTXTCHK keeps no state between runs.
;;; ======================================================================

(defun c:LINTXTCHK ( / *error* height spacing indent osm pt
                       startx y z x lvl txt undo-open )

  (defun *error* (msg)
    (if osm (setvar "OSMODE" osm))
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (setq undo-open nil)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nLINTXTCHK error: " msg)))
    (if lzd:report (lzd:report "LINTXTCHK" *lintxtchk-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "LINTXTCHK" *lintxtchk-version*))

  (setq height  ltc:*height*
        spacing (* height ltc:*spacing*)
        indent  (* height ltc:*indent*))

  (setq osm (getvar "OSMODE"))
  (setq pt (getpoint "\nPick top-left point for LINTXTCHK checklist: "))

  (if pt
    (progn
      (setvar "OSMODE" 0)                 ; drop osnaps while placing text
      ;; one undo group around the column - a U after LINTXTCHK takes
      ;; the whole checklist back at once instead of one entity per U
      ;; only when undo is recording - _Begin in a drawing with UNDO
      ;; off (bit 1 of UNDOCTL clear) errors out of the command
      (if (= 1 (logand 1 (getvar "UNDOCTL")))
        (progn
          (command "_.UNDO" "_Begin")
          (setq undo-open T)))
      (setq startx (car pt)
            y      (cadr pt)
            z      (if (caddr pt) (caddr pt) 0.0))
      (foreach item ltc:*items*
        (setq lvl (car item)
              txt (cdr item)
              x   (+ startx (* indent lvl)))
        (entmake
          (list
            '(0 . "TEXT")
            (cons 10 (list x y z))        ; insertion point (baseline, left)
            (cons 11 (list x y z))
            (cons 40 height)                   ; ltc:*height*
            (cons 1 (strcat ltc:*bullet* txt))  ; one entity per line
            '(72 . 0)                     ; horizontal justify: left
            '(73 . 0)                     ; vertical justify:   baseline
          )
        )
        (setq y (- y spacing))            ; step down to the next line
      )
      (setvar "OSMODE" osm)
      (if undo-open (command "_.UNDO" "_End"))
      (setq undo-open nil)
      (princ (strcat "\n" (itoa (length ltc:*items*))
                     " checklist lines placed at "
                     (rtos height 2 0) "\" text."))
    )
    (princ "\nLINTXTCHK cancelled.")
  )
  (princ)
)

(defun c:LINTXTCHKVER ()
  (princ (strcat "\nLINTXTCHK " *lintxtchk-version*))
  (princ))

(princ (strcat "\nLINTXTCHK " *lintxtchk-version*
               " loaded.  Type LINTXTCHK to place the liner checklist."))
(princ)
