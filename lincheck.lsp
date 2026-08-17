;;; ===================================================================
;;; LINCHECK.LSP - Liner tech drawing checklist
;;;
;;; Interactive AutoLISP routine that runs down the liner drawing
;;; checklist one item at a time, prompting the tech to complete /
;;; answer each item, then prints a report of everything that was
;;; checked, answered, and noted along the way.
;;;
;;; Load with APPLOAD (or (load "lincheck.lsp")) and run the
;;; LINCHECK command.
;;; ===================================================================

;;; ------------------------------------------------------------------
;;; Helpers
;;; ------------------------------------------------------------------

(setq *lin:log* nil)   ; collected report lines

;; Record a line for the report.
(defun lin:log (msg)
  (setq *lin:log* (append *lin:log* (list msg)))
  msg
)

;; Section header - printed to the command line and added to the report.
(defun lin:head (title)
  (princ (strcat "\n\n=== " title " ==="))
  (lin:log "")
  (lin:log (strcat "== " title " =="))
)

;; Simple check-off item.  Shows the item, waits for the tech to press
;; Enter when done (or type a note/value to record with it).
(defun lin:check (item / val)
  (setq val (getstring T (strcat "\n[ ] " item
                                 "\n      (Enter = done, or type a note): ")))
  (if (= val "")
    (lin:log (strcat "[x] " item))
    (lin:log (strcat "[x] " item " -- " val))
  )
  val
)

;; Ask the user to pick one keyword out of a list.
(defun lin:ask (prompt kwlist / ans)
  (while (not ans)
    (initget 1 kwlist)
    (setq ans (getkword (strcat "\n" prompt " ["
                                (vl-string-translate " " "/" kwlist) "]: ")))
  )
  (lin:log (strcat "[x] " prompt " -> " ans))
  ans
)

;; Yes/No convenience wrapper.  Returns T for Yes, nil for No.
(defun lin:yesno (prompt)
  (= (lin:ask prompt "Yes No") "Yes")
)

;; Ask for a value; records the value, or "NA" if none was provided.
(defun lin:value (label / val)
  (setq val (getstring T (strcat "\n    " label " (value or NA): ")))
  (if (or (= val "") (= (strcase val) "NA") (= (strcase val) "N/A"))
    (lin:log (strcat "    " label ": NA (not provided)"))
    (lin:log (strcat "    " label ": " val))
  )
  val
)

;;; ------------------------------------------------------------------
;;; Checklist
;;; ------------------------------------------------------------------

(defun c:LINCHECK (/ straightradius)
  (setq *lin:log* nil)
  (princ "\n--- Liner Tech Drawing Checklist ---")
  (princ "\nWork down each item; the report prints at the end.\n")

  ;; -- Job review --------------------------------------------------
  (lin:head "Job Review")
  (lin:check "Read all WSN (White Screen Notes), Notes from Merlin, and Customer Info")
  (if (not (lin:yesno "Does this job actually require a Tech drawing?"))
    (progn
      (lin:log "")
      (lin:log ">> Job does NOT require a Tech drawing - stopping checklist.")
      (lin:report)
    )
    (lin:run-rest)   ; job needs a drawing: run the rest of the checklist
  )
  (princ)
)

;; Remainder of the checklist (everything after the "requires a drawing?" gate).
(defun lin:run-rest (/ straightradius)
  ;; -- Walls & depth ----------------------------------------------
  (lin:head "Walls & Depth")
  (lin:check "Verify Finished Wall Ht & Pool Depth")
  (lin:value "Finished Wall Ht (single value, or \"Varies\")")

  ;; -- Liner pattern & bead ---------------------------------------
  (lin:head "Liner Pattern & Bead")
  (lin:check "Place liner pattern block (GLP) - delete \"Not Supplied\" text")
  (lin:value "Pool bead type / overlap (AG, etc.)")

  ;; -- Dimensions & orientation -----------------------------------
  (lin:head "Dimensions & Orientation")
  (lin:check "Pool perimeter & overall dims")
  (lin:check "Verify orientation: Shallow end to the RIGHT of page")

  ;; Report ALL cross dimensions provided by the customer.
  (princ "\nReport ALL cross dimensions provided by customer.")
  (princ "\n  Enter each as label=value (e.g. A-C=24'6\"), or NA. Blank line to finish.")
  (lin:log "[x] Cross dimensions provided by customer:")
  (lin:crossdims)

  ;; -- Corners -----------------------------------------------------
  (lin:head "Corners")
  (lin:check "Pool corners with dimensions")
  (lin:check (strcat "Watch for special mfgrs: Esther Williams (3x3, 5x5) "
                     "or Foxx (37\" Deep)"))

  ;; -- Special bottom conditions ----------------------------------
  (lin:head "Special Bottom Conditions")
  (lin:yesno "Does the shallow end have a Cove?")
  (lin:yesno "Does the pool have a Safety Ledge?")
  (lin:yesno "Did the customer provide various depths for the bottom?")
  (lin:yesno "Does the pool require a side view?")

  ;; -- Bottom / trowel --------------------------------------------
  (lin:head "Bottom & Trowel Lines")
  (lin:yesno "Are hopper corners radius?")
  (lin:check "Draw trowel lines accurately")

  ;; -- Fiberglass steps / bench -----------------------------------
  (lin:head "Steps / Bench - Fiberglass")
  (if (lin:yesno "Are steps / bench Fiberglass?")
    (progn
      (lin:check "Place FGS note or draw step outline if dimensions were provided")
      (setq straightradius (lin:ask "Is the step Straight or Radius? (ask if not given)"
                                    "Straight Radius"))
    )
  )

  ;; -- Vinyl-covered steps / bench --------------------------------
  (lin:head "Steps / Bench - Vinyl-Covered")
  (if (lin:yesno "Are steps / bench Vinyl-covered?")
    (progn
      (lin:check "Verify step corner type & dimensions")
      (lin:check "Place Step Attachment block")
      (lin:yesno "Is the attachment type provided?")
      (lin:check "Place side views for all steps and benches")
    )
  )

  ;; -- Final -------------------------------------------------------
  (lin:head "Final")
  (lin:check "Did you scale the titleblock?  ** REDVIEW! **")

  (lin:report)
)

;; Collect the customer's cross dimensions (loop until a blank entry).
(defun lin:crossdims (/ entry n)
  (setq n 0)
  (while (/= "" (setq entry (getstring T "\n  Cross dim (label=value / NA, blank to finish): ")))
    (setq n (1+ n))
    (lin:log (strcat "    " entry))
  )
  (if (= n 0)
    (lin:log "    (none provided)")
  )
)

;; Print the collected report.
(defun lin:report ()
  (princ "\n\n")
  (princ "############################################")
  (princ "\n#          LINER CHECKLIST REPORT          #")
  (princ "\n############################################")
  (foreach line *lin:log*
    (princ (strcat "\n" line))
  )
  (princ "\n############################################")
  (princ "\n")
  (princ)
)

(princ "\nLINCHECK.LSP loaded. Type LINCHECK to run the liner checklist.")
(princ)
