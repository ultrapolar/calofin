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
;; whatever a given machine has.
(setq calofin:*commands*
  '("SPA" "POOL" "POOLDEMO" "ABHD" "ABCDEF" "PADDLE" "AUTOBEAD"
    "CHECK" "LINCHECK" "DIMCHECK" "DIMSCAN" "COVERCHECK" "COVERSCAN"
    "LINTXTCHK" "MATCHSTD" "ACADY-SCAN"
    "AUTODIM" "STAIRDIM" "FLOORDIM" "DIMCONTEND" "DIMARCCHECK"
    "PERPPTS" "TYDRN" "CORNERSTP" "HEMISTEP" "WCALST" "ADAB"))

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
