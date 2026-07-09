;;; acady-loader.lsp
;;; Entry point. APPLOAD this file; it loads all modules from its own folder.
;;; Commands: MATCHSTD, MATCHSTD-CFG, ACADY-DUMPSIG (dev), ACADY-SCAN (dev)

(vl-load-com)

(defun acady--self-dir (/ p)
  ;; folder this loader lives in (works wherever the sources are copied)
  (setq p (findfile "acady-loader.lsp"))
  (if p (vl-filename-directory p) ""))

(setq *acady-dir* (acady--self-dir))

(defun acady--load (name / f)
  (setq f (strcat *acady-dir* "\\" name))
  (if (findfile f)
    (progn (load f) t)
    (progn (princ (strcat "\n[acady] MISSING MODULE: " name)) nil)))

;; load order matters: util -> config -> geom -> dbx -> tol -> cache -> match -> ui
(foreach m '("acady-util.lsp" "acady-config.lsp" "acady-geom.lsp"
             "acady-dbx.lsp" "acady-tol.lsp" "acady-cache.lsp"
             "acady-match.lsp" "acady-ui.lsp")
  (acady--load m))

;; user settings override defaults
(if acady-cfg-load (acady-cfg-load))

;; ---------------------------------------------------------------- selection

(defun acady-get-selection-objs (/ ss i objs)
  ;; prompt for entities; return list of VLA objects (nil if none)
  (princ "\nSelect the outline to check against standards: ")
  (setq ss (ssget '((0 . "LWPOLYLINE,POLYLINE,LINE,ARC,CIRCLE"))))
  (if ss
    (progn
      (setq i 0 objs nil)
      (while (< i (sslength ss))
        (setq objs (cons (vlax-ename->vla-object (ssname ss i)) objs))
        (setq i (1+ i)))
      (setq *acady-last-objs* (reverse objs)))
    (setq *acady-last-objs* nil)))

(defun acady-selection-sigs (/ objs r)
  ;; -> (sigs . err-or-nil), logging skipped entity types
  (setq objs (acady-get-selection-objs))
  (if objs
    (progn
      (setq r (acady-objs->sigs objs))
      (if (cadr r)
        (acady-log (strcat "ignored unsupported entities: "
                           (acady-str-join (cadr r) ", "))))
      (cons (car r) (caddr r)))
    (cons nil "nothing selected")))

;; ---------------------------------------------------------------- dev: dump

(defun c:ACADY-DUMPSIG (/ r sigs m)
  (setq r (acady-selection-sigs))
  (cond
    ((cdr r) (acady-log (strcat "error: " (cdr r))))
    ((null (car r)) (acady-log "no usable geometry in selection."))
    (t
     (setq sigs (car r))
     (acady-log (strcat (itoa (length sigs)) " path(s) extracted:"))
     (foreach sig sigs
       (acady-print-sig sig)
       ;; print the mirrored form too so M1 mirror tests can be eyeballed
       (setq m (acady-sig-mirror sig))
       (acady-log "mirrored form:")
       (acady-print-sig m))))
  (princ))

(princ "\n[acady] loaded. Commands: MATCHSTD, MATCHSTD-CFG, ACADY-DUMPSIG, ACADY-SCAN")
(princ)
