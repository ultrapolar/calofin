;;; acady-cache.lsp
;;; Signature cache for the standards folder so DWGs aren't re-parsed via
;;; ObjectDBX on every run. One s-expression file:
;;;   (ACADY-CACHE <fmt-ver>
;;;     (("pacific.dwg" (SYSTIME ...) (SIZE . n) (SIG . sig) (TOL . bands)
;;;       (WARN . (...)))
;;;      ...))
;;; Invalidation: per-entry on systime/size change; whole cache on format or
;;; signature version mismatch or any read error. Corrupt cache never throws.

(setq *acady-cache-ver* 1)

(defun acady-cache-path (/ folder f fh)
  ;; shared cache in the standards folder if writable, else per-user temp
  (setq folder (acady-cfg "STDFOLDER"))
  (setq f (strcat folder "\\acady-cache.dat"))
  (setq fh (acady-catch 'open (list f "a")))
  (if fh
    (progn (close fh) f)
    (strcat (getvar "TEMPPREFIX") "acady-cache.dat")))

(defun acady-cache-read (path / fh txt line form entries)
  ;; -> entry alist keyed by bare filename, or nil
  (if (and path (findfile path))
    (progn
      (setq fh (open path "r") txt "")
      (if fh
        (progn
          (while (setq line (read-line fh))
            (setq txt (strcat txt line "\n")))
          (close fh)
          (setq form (acady-catch 'read (list txt)))
          (if (and form
                   (eq (car form) 'ACADY-CACHE)
                   (= (cadr form) *acady-cache-ver*))
            (caddr form)
            (progn
              (if form (acady-dbg "cache version mismatch — rebuilding"))
              nil)))
        nil))
    nil))

(defun acady-cache-write (path entries / tmp fh)
  ;; atomic-ish: write tmp, delete old, rename
  (setq tmp (strcat path ".tmp"))
  (setq fh (acady-catch 'open (list tmp "w")))
  (if fh
    (progn
      (prin1 (list 'ACADY-CACHE *acady-cache-ver* entries) fh)
      (close fh)
      (if (findfile path) (vl-file-delete path))
      (vl-file-rename tmp path)
      t)
    (progn (acady-dbg (strcat "cannot write cache at " path)) nil)))

(defun acady-cache-entry-fresh-p (entry path / st sz)
  (setq st (vl-file-systime path)
        sz (vl-file-size path))
  (and entry st sz
       (equal (cdr (assoc 'SYSTIME (cdr entry))) st)
       (equal (cdr (assoc 'SIZE (cdr entry))) sz)
       ;; embedded signature version must match the code's
       (= (acady-aget "VER" (cdr (assoc 'SIG (cdr entry)))) *acady-sig-ver*)))

(defun acady-make-entry (fname path sig tol warns)
  (list fname
        (cons 'SYSTIME (vl-file-systime path))
        (cons 'SIZE (vl-file-size path))
        (cons 'SIG sig)
        (cons 'TOL tol)
        (cons 'WARN warns)))

(defun acady-entry-get (entry key) (cdr (assoc key (cdr entry))))

;; ---------------------------------------------------------------- scanning

(defun acady-scan-standards (force / folder files cache path fname entry fresh
                                   parsed out changed)
  ;; -> list of live entries for every DWG in the standards folder.
  ;; force = T ignores the cache entirely (Rescan button).
  (setq folder (acady-cfg "STDFOLDER"))
  (cond
    ((or (null folder) (= folder ""))
     (acady-log "standards folder not set — run MATCHSTD-CFG first.")
     nil)
    ((not (vl-file-directory-p folder))
     (acady-log (strcat "standards folder missing: " folder))
     nil)
    (t
     (setq path (acady-cache-path))
     (setq cache (if force nil (acady-cache-read path)))
     (setq files (acady-dbx-folder-files folder))
     (if (null files)
       (acady-log (strcat "no DWG files in " folder)))
     (setq out nil changed nil)
     (foreach f files
       (setq fname (strcase (vl-filename-base f) t))
       (setq fname (strcat fname ".dwg"))
       (setq entry (assoc fname cache))
       (if (and entry (acady-cache-entry-fresh-p entry f))
         (progn
           (acady-dbg (strcat fname ": cached"))
           (setq out (cons entry out)))
         (progn
           (acady-log (strcat "parsing " fname " ..."))
           (setq parsed (acady-parse-standard f))
           (if parsed
             (progn
               (setq out (cons (acady-make-entry fname f
                                                 (car parsed)     ; sig
                                                 (cadr parsed)    ; tol bands
                                                 (caddr parsed))  ; warnings
                               out))
               (setq changed t))
             (acady-log (strcat "skipped " fname ": "
                                (if *acady-scan-err* *acady-scan-err* "unreadable")))))))
     ;; entries for deleted files drop out naturally (we only keep found files)
     (if (or changed (and cache (/= (length cache) (length out))) (null cache))
       (acady-cache-write path (reverse out)))
     (setq *acady-standards* (reverse out))
     (if files (acady-log (strcat (itoa (length out)) " standard(s) ready.")))
     (gc) ; flush released DBX wrappers after a full scan
     (reverse out))))

(defun acady-parse-standard (path / r)
  ;; open one reference DWG, extract nominal signature + tolerance bands.
  ;; -> (sig bands warnings) or nil (with *acady-scan-err* set)
  (setq *acady-scan-err* nil)
  (setq r (acady-dbx-with-doc path 'acady-space->standard))
  (if (car r)
    (if (cadr r)
      (cadr r)
      (progn (setq *acady-scan-err* "no closed outline found") nil))
    (progn (setq *acady-scan-err* (cadr r)) nil)))

;; ---------------------------------------------------------------- dev: scan

(defun c:ACADY-SCAN (/ entries)
  (setq entries (acady-scan-standards nil))
  (foreach e entries
    (acady-log (strcat "=== " (strcase (vl-filename-base (car e))) " ==="))
    (acady-print-sig (acady-entry-get e 'SIG))
    (acady-log (strcat "tolerance source: "
                       (acady-aget "BANDSRC" (acady-entry-get e 'TOL))))
    (foreach w (acady-entry-get e 'WARN)
      (acady-log (strcat "warning: " w))))
  (princ))

(princ "\n[acady] cache loaded.")
(princ)
