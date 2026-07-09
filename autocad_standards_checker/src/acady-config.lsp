;;; acady-config.lsp
;;; Global configuration for the standards matcher.
;;; Persisted per-user to acady-user.lsp in the same folder as this file
;;; (falls back to TEMPPREFIX if not writable) — file-based, BricsCAD-portable.

;; defaults; drawing units assumed inches (architectural)
(setq *acady-cfg*
  (list
    (cons "STDFOLDER"  "")            ; standards folder; set via MATCHSTD-CFG
    (cons "TOL-LAYER"  "TOLERANCE")   ; reserved layer for tolerance geometry/text
    (cons "NOM-LAYER"  "STD-NOMINAL") ; preferred layer for the nominal outline
    (cons "TOL-LEN"    0.25)          ; global default length tolerance, ± inches
    (cons "TOL-RAD"    6.0)           ; global default radius tolerance, ± inches
    (cons "TOL-ANG"    (/ (* 2.0 pi) 180.0)) ; global default angle tol, ±2 deg in rad
    (cons "T2-THRESH"  0.35)          ; Tier-2 minimum report score
    (cons "HL-COLOR"   1)             ; feature-highlight marker color (red)
    (cons "TMP-LAYER"  "ACADY-TMP"))) ; temp layer for feature markers

(defun acady-cfg (key) (acady-aget key *acady-cfg*))

(defun acady-cfg-set (key val)
  (setq *acady-cfg* (acady-aput key val *acady-cfg*)))

;; -------------------------------------------------------------- persistence

(defun acady-cfg-file (/ self dir)
  ;; user settings file next to the sources, else TEMPPREFIX
  (setq self (findfile "acady-config.lsp"))
  (setq dir (if self (vl-filename-directory self) (getvar "TEMPPREFIX")))
  (strcat dir "\\acady-user.lsp"))

(defun acady-cfg-save (/ f fh)
  (setq f (acady-cfg-file))
  (setq fh (open f "w"))
  (if fh
    (progn
      (princ ";; acady user settings — auto-generated, edit via MATCHSTD-CFG\n" fh)
      (foreach pair *acady-cfg*
        (princ "(acady-cfg-set " fh)
        (prin1 (car pair) fh)
        (princ " " fh)
        (prin1 (cdr pair) fh)
        (princ ")\n" fh))
      (close fh)
      (acady-log (strcat "settings saved to " f)))
    (acady-log (strcat "could not write settings to " f))))

(defun acady-cfg-load (/ f)
  (setq f (acady-cfg-file))
  (if (findfile f)
    (acady-catch 'load (list f))))

;; -------------------------------------------------------------- CFG command

(defun c:MATCHSTD-CFG (/ cur f new)
  (setq cur (acady-cfg "STDFOLDER"))
  (acady-log (strcat "current standards folder: "
                     (if (= cur "") "<not set>" cur)))
  ;; getfiled on any DWG inside the folder is the portable "folder picker"
  (setq f (getfiled "Pick any DWG inside the standards folder"
                    (if (= cur "") "" (strcat cur "\\")) "dwg" 0))
  (if f
    (progn
      (setq new (vl-filename-directory f))
      (acady-cfg-set "STDFOLDER" new)
      (acady-cfg-save)
      (acady-log (strcat "standards folder set to " new)))
    (acady-log "unchanged."))
  (princ))

(princ "\n[acady] config loaded.")
(princ)
