;;; ==========================================================================
;;; LINTXTCHK.lsp  --  Liner Text Checklist
;;; --------------------------------------------------------------------------
;;; Places the vinyl pool-liner drawing checklist into the current drawing as
;;; a column of individual TEXT entities (one entity per line) starting at a
;;; point the user picks.  Text height is 12" and the lines are spaced out
;;; vertically automatically.  Sub-items are indented under their parent.
;;;
;;; Usage:  APPLOAD this file (or add it to your startup suite), then type
;;;         LINTXTCHK and pick the top-left point for the checklist.
;;; ==========================================================================

(setq *lintxtchk-version* "v1.1")   ; announced on load; release_lisp.py
                                       ; stamps the dated twin in releases/

(defun c:LINTXTCHK ( / *error* items height spacing indent osm pt
                       startx y z x lvl txt undo-open )

  (defun *error* (msg)
    (if osm (setvar "OSMODE" osm))
    (if undo-open (command "_.UNDO" "_End"))
    (setq undo-open nil)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nLINTXTCHK error: " msg)))
    (princ))

  ;; --- the checklist -------------------------------------------------------
  ;; Each entry is (indent-level . "line text").  Level 0 = main item,
  ;; level 1 = sub-item.  Inner double quotes and inch marks are escaped.
  (setq items
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

  ;; --- layout parameters ---------------------------------------------------
  (setq height  12.0)            ; text height  = 12"
  (setq spacing (* height 1.6))  ; automatic vertical distance between lines
  (setq indent  (* height 1.5))  ; horizontal indent per sub-level

  (setq osm (getvar "OSMODE"))
  (setq pt (getpoint "\nPick top-left point for LINTXTCHK checklist: "))

  (if pt
    (progn
      (setvar "OSMODE" 0)                 ; drop osnaps while placing text
      ;; one undo group around the column - a U after LINTXTCHK takes
      ;; back all 26 lines at once instead of one entity per U
      (command "_.UNDO" "_Begin")
      (setq undo-open T)
      (setq startx (car pt)
            y      (cadr pt)
            z      (if (caddr pt) (caddr pt) 0.0))
      (foreach item items
        (setq lvl (car item)
              txt (cdr item)
              x   (+ startx (* indent lvl)))
        (entmake
          (list
            '(0 . "TEXT")
            (cons 10 (list x y z))        ; insertion point (baseline, left)
            (cons 11 (list x y z))
            (cons 40 height)             ; 12" text
            (cons 1 (strcat "- " txt))   ; each line is its own entity
            '(72 . 0)                     ; horizontal justify: left
            '(73 . 0)                     ; vertical justify:   baseline
          )
        )
        (setq y (- y spacing))            ; step down to the next line
      )
      (setvar "OSMODE" osm)
      (if undo-open (command "_.UNDO" "_End"))
      (setq undo-open nil)
      (princ (strcat "\n" (itoa (length items))
                     " checklist lines placed at 12\" text."))
    )
    (princ "\nLINTXTCHK cancelled.")
  )
  (princ)
)

(princ "\nLINTXTCHK loaded.  Type LINTXTCHK to place the liner checklist.")
(princ)
