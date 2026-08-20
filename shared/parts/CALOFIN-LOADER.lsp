;;; ======================================================================
;;; CALOFIN-LOADER.lsp  --  load the whole calofin shared build at once
;;; ----------------------------------------------------------------------
;;; APPLOAD this one file.  It loads CALOFIN-LIB.lsp first, then every
;;; tool beside it -- the shared build assumes everything is loaded
;;; together, so this is the only supported way to load it.  (The
;;; standalone builds live in lisp/ and load one file at a time; do not
;;; mix the two in a session.)
;;; ======================================================================

(vl-load-com)

;;; -------------------- finding this folder -----------------------------
;;; APPLOAD hands AutoCAD a full path out of its own file dialog, but it
;;; does NOT add that folder to the support file search path.  So
;;; (findfile "CALOFIN-LOADER.lsp") comes back nil whenever the build is
;;; APPLOADed from a folder AutoCAD does not already search -- a
;;; Downloads folder, a memory stick -- and the loader cannot see its own
;;; siblings even though it is sitting right beside them.  Four ways in,
;;; the ones that need nothing from the user first; the answer is
;;; remembered, so at most the first load ever asks.

(setq cal:*regkey* "HKEY_CURRENT_USER\\Software\\Calofin")

;; T when DIR is really a calofin build folder, not just any folder
(defun cal--has-lib (dir)
  (and dir (= (type dir) 'STR) (/= dir "")
       (findfile (strcat dir "\\CALOFIN-LIB.lsp"))))

(defun cal--remembered ( / d)
  (setq d (vl-catch-all-apply 'vl-registry-read
                              (list cal:*regkey* "SharedDir")))
  (if (vl-catch-all-error-p d) nil d))

(defun cal--remember (dir)
  (vl-catch-all-apply 'vl-registry-write
                      (list cal:*regkey* "SharedDir" dir))
  dir)

(defun cal--ask ( / f)
  (princ "\n[calofin] Cannot see the rest of the build from here.")
  (princ "\n[calofin] Pick CALOFIN-LIB.lsp out of the same folder --")
  (princ "\n[calofin] this is asked once and then remembered.")
  (setq f (getfiled "Select CALOFIN-LIB.lsp" "" "lsp" 0))
  (if f (vl-filename-directory f)))

(defun cal--find-dir ( / p d)
  (cond
    ;; 1. set by hand before loading, or left over from an earlier load
    ((cal--has-lib cal:*dir*) cal:*dir*)
    ;; 2. the folder is on the support file search path
    ((setq p (findfile "CALOFIN-LIB.lsp")) (vl-filename-directory p))
    ;; 3. where a previous session found it
    ((cal--has-lib (setq d (cal--remembered))) d)
    ;; 4. ask, and remember the answer
    ((cal--has-lib (setq d (cal--ask))) (cal--remember d))))

(setq cal:*dir* (cal--find-dir)
      cal:*missing* 0)

;; Look beside the loader first, then anywhere AutoCAD searches.
(defun cal--load (name / f)
  (setq f (cond ((and cal:*dir* (findfile (strcat cal:*dir* "\\" name))))
                ((findfile name))))
  (cond (f (load f) t)
        (t (setq cal:*missing* (1+ cal:*missing*))
           (princ (strcat "\n[calofin] MISSING: " name))
           nil)))

;;; -------------------- the build ---------------------------------------

(if (not cal:*dir*)
  (progn
    (princ "\n[calofin] Could not locate the build folder - nothing loaded.")
    (princ "\n[calofin] Either add the folder holding CALOFIN-LIB.lsp to")
    (princ "\n[calofin] Options > Files > Support File Search Path, or set")
    (princ "\n[calofin] cal:*dir* to that folder before loading this file."))
  (progn
    (princ (strcat "\n[calofin] build folder: " cal:*dir*))
    (setq cal:*build-loading* T)   ; the library arrives as part of a build
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
                 "STOCKCOVER.lsp" "drone.lsp" "wcalst.lsp" "xftconv.lsp")
      (cal--load m))
    (if (> cal:*missing* 0)
      (princ (strcat "\n[calofin] " (itoa cal:*missing*)
                     " file(s) missing - the build folder is incomplete."))
      (princ "\n[calofin] shared build loaded - every command in one session."))
    (princ "\n[calofin] Type CALVER for the library version.")))

(princ)
