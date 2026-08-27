;;; ===================================================================
;;; LINCHECK.LSP - Liner tech drawing checklist
;;;
;;; Interactive AutoLISP routine that runs down the liner drawing
;;; checklist one item at a time, prompting the tech to complete /
;;; answer each item, then prints a report of everything that was
;;; checked, answered, and noted along the way.
;;;
;;; Every item after the first also offers Back (type B; Undo works
;;; too), which re-asks the previous item and drops what it logged -
;;; a mis-answered question never means Esc and a fresh start.  At the
;;; typed prompts (notes, values, cross dims) Back is typed like a
;;; note: B, BACK, U or UNDO alone, any case.
;;;
;;; Load with APPLOAD (or (load "lincheck.lsp")) and run the
;;; LINCHECK command.
;;; ===================================================================
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.

;;; ------------------------------------------------------------------
;;; Helpers
;;; ------------------------------------------------------------------

(setq *lincheck-version* "v1.0")   ; announced on load; release_lisp.py
                                      ; stamps the dated twin in releases/

(setq *lin:log* nil)   ; collected report lines

;; Record a line for the report.
(defun lin:log (msg)
  (setq *lin:log* (append *lin:log* (list msg)))
  msg
)

;; Keep only the first N report lines - the rollback when a Back drops
;; what an item logged.
(defun lin:trim (n / out i)
  (setq out nil i 0)
  (foreach l *lin:log*
    (if (< i n) (setq out (cons l out)))
    (setq i (1+ i))
  )
  (setq *lin:log* (reverse out))
)

;; Section header - printed to the command line and added to the report.
(defun lin:head (title)
  (princ (strcat "\n\n=== " title " ==="))
  (lin:log "")
  (lin:log (strcat "== " title " =="))
)

;; Simple check-off item.  Shows the item, waits for the tech to press
;; Enter when done (or type a note/value to record with it).  With back
;; non-nil, B (Back) returns the symbol LIN-BACK instead of logging.
(defun lin:check (item back / val)
  (setq val (getstring T (strcat "\n[ ] " item
                                 "\n      (Enter = done"
                                 (if back ", B = back" "")
                                 ", or type a note): ")))
  (cond
    ((and back (cal:back-word-p val)) 'LIN-BACK)
    ((= val "") (lin:log (strcat "[x] " item)) val)
    (T (lin:log (strcat "[x] " item " -- " val)) val)
  )
)

;; Ask the user to pick one keyword out of a list.  With back non-nil
;; the choices also take Back (Undo accepted as a hidden synonym),
;; returning the symbol LIN-BACK.
(defun lin:ask (prompt kwlist back / ans)
  (while (not ans)
    (initget 1 (if back (strcat kwlist " Back Undo") kwlist))
    (setq ans (getkword (strcat "\n" prompt " ["
                                (vl-string-translate " " "/" kwlist)
                                (if back "/Back" "") "]: ")))
  )
  (if (member ans '("Back" "Undo"))
    'LIN-BACK
    (progn (lin:log (strcat "[x] " prompt " -> " ans)) ans)
  )
)

;; Yes/No convenience wrapper.  Returns T for Yes, nil for No, or the
;; symbol LIN-BACK.
(defun lin:yesno (prompt back / v)
  (setq v (lin:ask prompt "Yes No" back))
  (if (eq v 'LIN-BACK) v (= v "Yes"))
)

;; Ask for a value; records the value, or "NA" if none was provided.
;; With back non-nil, B (Back) returns the symbol LIN-BACK instead.
(defun lin:value (label back / val)
  (setq val (getstring T (strcat "\n    " label " (value or NA"
                                 (if back ", B = back" "") "): ")))
  (cond
    ((and back (cal:back-word-p val)) 'LIN-BACK)
    ((or (= val "") (= (strcase val) "NA") (= (strcase val) "N/A"))
     (lin:log (strcat "    " label ": NA (not provided)")) val)
    (T (lin:log (strcat "    " label ": " val)) val)
  )
)

;; Run the checklist as a list of one-question stages with Back between
;; them.  Each stage is (test-expr . fn): a stage whose test evaluates
;; nil is skipped, and tests are re-evaluated on every pass, so backing
;; up and changing an answer re-routes the branch.  A stage returning
;; LIN-BACK rewinds to the previous asked stage and drops everything
;; logged since just before it; LIN-STOP ends the run early (the report
;; still prints).  Stage 1 has nowhere to go back to, so it re-asks.
(defun lin:stages (fns / i n v it asked mark)
  (setq i 0 n (length fns) asked nil)
  (while (< i n)
    (setq it (nth i fns))
    (if (and (car it) (not (eval (car it))))
      (setq i (1+ i))                       ; branch not taken - skip
      (progn
        (setq mark (length *lin:log*)
              v    (apply (cdr it) nil))
        (cond
          ((eq v 'LIN-BACK)
           (lin:trim mark)                  ; drop the aborted item's log
           (if asked
             (progn
               (setq i (caar asked))
               (lin:trim (cdar asked))
               (setq asked (cdr asked))
             )
             (princ "\n  Already at the first item.")
           ))
          ((eq v 'LIN-STOP) (setq i n))
          (T
           (setq asked (cons (cons i mark) asked)
                 i     (1+ i))
          )
        )
      )
    )
  )
)

;;; ------------------------------------------------------------------
;;; Checklist stages (one question each; heads travel with the first
;;; question under them so a Back re-prints the section header too)
;;; ------------------------------------------------------------------

(defun lin:st-read ()
  (lin:head "Job Review")
  (lin:check "Read all WSN (White Screen Notes), Notes from Merlin, and Customer Info" nil)
)

(defun lin:st-gate (/ v)
  (setq v (lin:yesno "Does this job actually require a Tech drawing?" T))
  (cond
    ((eq v 'LIN-BACK) v)
    ((null v)
     (lin:log "")
     (lin:log ">> Job does NOT require a Tech drawing - stopping checklist.")
     'LIN-STOP)
    (T v)
  )
)

(defun lin:st-wallht-chk ()
  (lin:head "Walls & Depth")
  (lin:check "Verify Finished Wall Ht & Pool Depth" T)
)

(defun lin:st-wallht-val ()
  (lin:value "Finished Wall Ht (single value, or \"Varies\")" T)
)

(defun lin:st-glp ()
  (lin:head "Liner Pattern & Bead")
  (lin:check "Place liner pattern block (GLP) - delete \"Not Supplied\" text" T)
)

(defun lin:st-bead ()
  (lin:value "Pool bead type / overlap (AG, etc.)" T)
)

(defun lin:st-perim ()
  (lin:head "Dimensions & Orientation")
  (lin:check "Pool perimeter & overall dims" T)
)

(defun lin:st-orient ()
  (lin:check "Verify orientation: Shallow end to the RIGHT of page" T)
)

(defun lin:st-crossdims ()
  ;; Report ALL cross dimensions provided by the customer.
  (princ "\nReport ALL cross dimensions provided by customer.")
  (princ "\n  Enter each as label=value (e.g. A-C=24'6\"), or NA. Blank line to finish.")
  (lin:log "[x] Cross dimensions provided by customer:")
  (lin:crossdims T)
)

(defun lin:st-corners ()
  (lin:head "Corners")
  (lin:check "Pool corners with dimensions" T)
)

(defun lin:st-mfgrs ()
  (lin:check (strcat "Watch for special mfgrs: Esther Williams (3x3, 5x5) "
                     "or Foxx (37\" Deep)") T)
)

(defun lin:st-cove ()
  (lin:head "Special Bottom Conditions")
  (lin:yesno "Does the shallow end have a Cove?" T)
)

(defun lin:st-ledge ()
  (lin:yesno "Does the pool have a Safety Ledge?" T)
)

(defun lin:st-depths ()
  (lin:yesno "Did the customer provide various depths for the bottom?" T)
)

(defun lin:st-sideview ()
  (lin:yesno "Does the pool require a side view?" T)
)

(defun lin:st-hopper ()
  (lin:head "Bottom & Trowel Lines")
  (lin:yesno "Are hopper corners radius?" T)
)

(defun lin:st-trowel ()
  (lin:check "Draw trowel lines accurately" T)
)

(defun lin:st-fib (/ v)
  (lin:head "Steps / Bench - Fiberglass")
  (setq v (lin:yesno "Are steps / bench Fiberglass?" T))
  (if (not (eq v 'LIN-BACK)) (setq fib v))
  v
)

(defun lin:st-fib-note ()
  (lin:check "Place FGS note or draw step outline if dimensions were provided" T)
)

(defun lin:st-fib-type ()
  (lin:ask "Is the step Straight or Radius? (ask if not given)"
           "Straight Radius" T)
)

(defun lin:st-vin (/ v)
  (lin:head "Steps / Bench - Vinyl-Covered")
  (setq v (lin:yesno "Are steps / bench Vinyl-covered?" T))
  (if (not (eq v 'LIN-BACK)) (setq vin v))
  v
)

(defun lin:st-vin-corner ()
  (lin:check "Verify step corner type & dimensions" T)
)

(defun lin:st-vin-attach ()
  (lin:check "Place Step Attachment block" T)
)

(defun lin:st-vin-attype ()
  (lin:yesno "Is the attachment type provided?" T)
)

(defun lin:st-vin-side ()
  (lin:check "Place side views for all steps and benches" T)
)

(defun lin:st-final ()
  (lin:head "Final")
  (lin:check "Did you scale the titleblock?  ** REDVIEW! **" T)
)

;;; ------------------------------------------------------------------
;;; Checklist
;;; ------------------------------------------------------------------

(defun c:LINCHECK (/ fib vin)
  (setq *lin:log* nil fib nil vin nil)
  (princ "\n--- Liner Tech Drawing Checklist ---")
  (princ "\nWork down each item; the report prints at the end.")
  (princ "\n(after the first item, Back re-asks the previous one)\n")
  (lin:stages (list
    (cons nil  'lin:st-read)
    (cons nil  'lin:st-gate)
    (cons nil  'lin:st-wallht-chk)
    (cons nil  'lin:st-wallht-val)
    (cons nil  'lin:st-glp)
    (cons nil  'lin:st-bead)
    (cons nil  'lin:st-perim)
    (cons nil  'lin:st-orient)
    (cons nil  'lin:st-crossdims)
    (cons nil  'lin:st-corners)
    (cons nil  'lin:st-mfgrs)
    (cons nil  'lin:st-cove)
    (cons nil  'lin:st-ledge)
    (cons nil  'lin:st-depths)
    (cons nil  'lin:st-sideview)
    (cons nil  'lin:st-hopper)
    (cons nil  'lin:st-trowel)
    (cons nil  'lin:st-fib)
    (cons 'fib 'lin:st-fib-note)
    (cons 'fib 'lin:st-fib-type)
    (cons nil  'lin:st-vin)
    (cons 'vin 'lin:st-vin-corner)
    (cons 'vin 'lin:st-vin-attach)
    (cons 'vin 'lin:st-vin-attype)
    (cons 'vin 'lin:st-vin-side)
    (cons nil  'lin:st-final)
  ))
  (lin:report)
  (princ)
)

;; Collect the customer's cross dimensions (loop until a blank entry).
;; B (Back) removes the last entry, or - when there is none and back is
;; non-nil - leaves the stage with LIN-BACK.
(defun lin:crossdims (back / entry n done)
  (setq n 0 done nil)
  (while (not done)
    (setq entry (getstring T (strcat "\n  Cross dim (label=value / NA"
                                     ", B = back, blank to finish): ")))
    (cond
      ((cal:back-word-p entry)
       (if (> n 0)
         (progn
           (setq n (1- n))
           (lin:trim (1- (length *lin:log*)))
           (princ "\n  Stepping back one cross dim.")
         )
         (if back
           (setq done 'LIN-BACK)
           (princ "\n  Already at the first cross dim.")
         )
       ))
      ((= entry "") (setq done T))
      (T (setq n (1+ n)) (lin:log (strcat "    " entry)))
    )
  )
  (if (eq done 'LIN-BACK)
    'LIN-BACK
    (progn (if (= n 0) (lin:log "    (none provided)")) n)
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
