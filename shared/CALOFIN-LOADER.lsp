;;; ======================================================================
;;; CALOFIN-LOADER.lsp  --  load the whole calofin shared build at once
;;; ----------------------------------------------------------------------
;;; APPLOAD this one file.  It loads CALOFIN-LIB.lsp first, then every
;;; tool in this folder, then the drawing-standards matcher's modules --
;;; the shared build assumes everything is loaded together, so this is
;;; the only supported way to load it.  (The standalone builds live in
;;; lisp/ and load one file at a time; do not mix the two in a session.)
;;;
;;; The pattern follows lisp/standards_checker/src/acady-loader.lsp:
;;; self-locate via findfile, then load an ordered list.
;;; ======================================================================

(vl-load-com)

(defun cal--self-dir (/ p)
  ;; folder this loader lives in (works wherever the folder is copied)
  (setq p (findfile "CALOFIN-LOADER.lsp"))
  (if p (vl-filename-directory p) ""))

(setq cal:*dir* (cal--self-dir))

(defun cal--load (name / f)
  (setq f (strcat cal:*dir* "\\" name))
  (if (findfile f)
    (progn (load f) t)
    (progn (princ (strcat "\n[calofin] MISSING: " name)) nil)))

;; The library first -- every tool below calls into it.  POOL and SPA
;; precede their demo/tutorial satellites.
(foreach m '("CALOFIN-LIB.lsp"
             "POOL.lsp" "POOLDEMO.lsp" "TUTORIALPOOL.lsp"
             "SPA.lsp" "TUTORIALSPA.lsp"
             "abcdef.lsp" "ALTABCDEF.lsp" "abhd.lsp" "AUTOBEAD.lsp"
             "AutoDim.lsp" "BPCALLOUT.lsp" "ccprecheck.lsp"
             "CDCALLOUT.lsp" "CDCREATE.lsp" "check_drawing.lsp"
             "CORNERSTP.lsp" "HEMISTEP.lsp" "NORMIESTEP.lsp"
             "covercheck.lsp" "dimcheck.lsp" "dim_continue.lsp"
             "DroneDistortion.lsp" "DroneHeightGPS.lsp"
             "lhd.lsp" "lincheck.lsp" "linfincheck.lsp" "LINTXTCHK.lsp"
             "PADDLE.lsp" "perp_points.lsp" "cperp_points.lsp"
             "tutorial_perp_points.lsp" "tutorial_cperp_points.lsp"
             "STOCKCOVER.lsp" "tydrn.lsp" "wcalst.lsp" "xftconv.lsp")
  (cal--load m))

;; The drawing-standards matcher is its own module set (acady- prefix,
;; verbatim from lisp/standards_checker/src/); order matters:
;; util -> config -> geom -> dbx -> tol -> cache -> match -> ui
(foreach m '("acady-util.lsp" "acady-config.lsp" "acady-geom.lsp"
             "acady-dbx.lsp" "acady-tol.lsp" "acady-cache.lsp"
             "acady-match.lsp" "acady-ui.lsp")
  (cal--load (strcat "acady\\" m)))

;; user settings override the matcher's defaults
(if acady-cfg-load (acady-cfg-load))

(princ "\n[calofin] shared build loaded - every command in one session.")
(princ "\nType CALVER for the library version.")
(princ)
