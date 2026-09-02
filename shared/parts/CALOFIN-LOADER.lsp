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
  ;; the registry first, then the profile: on a locked-down machine
  ;; the registry copy was never written (see cal--remember), and the
  ;; profile is where the answer survived
  (if (or (vl-catch-all-error-p d) (null d))
      (getenv "CalofinSharedDir")
      d))

(defun cal--remember (dir)
  ;; vl-registry-write answers a denied HKCU with nil, not an error, so
  ;; the catch here never noticed -- and the loader asked the same
  ;; question again on every drawing opened.  The profile (setenv) is
  ;; always writable, so the answer goes there as well.
  (vl-catch-all-apply 'vl-registry-write
                      (list cal:*regkey* "SharedDir" dir))
  (setenv "CalofinSharedDir" dir)
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

;;; -------------------- held back from this build -----------------------
;;; These exist in shared/parts/ and in lisp/, but are deliberately NOT
;;; compiled into LAZPASS.lsp and not loaded here.  Two reasons,
;;; kept apart on purpose:
;;;   WIP      still being worked on - goes in when it settles
;;;   OMITTED  never part of calofin
;;; This list is the single source of truth: tools/build_shared_bundle.py
;;; and tools/check_standards.py both read it.  Move a name out of here
;;; and into the manifest above, then rebuild:
;;;     python3 tools/build_shared_bundle.py

(setq cal:*held-back*
  '(("LISPLAB.lsp" . "OMITTED")))     ; teaching tool - never part of calofin

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
    ;; precede their demo/tutorial satellites; LINGUTTER follows PADDLE,
    ;; which it hands its stripped drawing to; LAZFORM comes after POOL,
    ;; whose answers it fills in, and the LAZPANEL launcher loads last of
    ;; all, after everything its buttons name.
    (foreach m '(
                 "CALOFIN-LIB.lsp" "POOL.lsp" "POOLDEMO.lsp"
                 "TUTORIALPOOL.lsp" "POOLSIDE.lsp"
                 "SPA.lsp" "TUTORIALSPA.lsp"
                 "OASIS.lsp" "abcdef.lsp" "ABFIND.lsp"
                 "ALTABCDEF.lsp" "abhd.lsp" "ABCURCHECK.lsp" "ABPCHECK.lsp"
                 "CABHD.lsp" "POINTRENAMER.lsp" "AUTOBEAD.lsp"
                 "AutoDim.lsp" "BPCALLOUT.lsp" "ccprecheck.lsp"
                 "CDCALLOUT.lsp" "CDCREATE.lsp" "check_drawing.lsp"
                 "CORNERSTP.lsp" "HEMISTEP.lsp" "NORMIESTEP.lsp"
                 "LAZSTEP.lsp"
                 "covercheck.lsp" "CUSTBLOCK.lsp"
                 "dimcheck.lsp" "dim_continue.lsp"
                 "DroneDistortion.lsp" "DroneHeightGPS.lsp"
                 "FITABHD.lsp" "lhd.lsp" "lincheck.lsp"
                 "linfincheck.lsp" "LINTXTCHK.lsp" "PADDLE.lsp"
                 "LINGUTTER.lsp"
                 "perp_points.lsp" "cperp_points.lsp"
                 "tutorial_perp_points.lsp" "tutorial_cperp_points.lsp"
                 "SMARTFILLET.lsp" "SPACHECK.lsp"
                 "STOCKCOVER.lsp" "drone.lsp" "tydrn.lsp"
                 "SOCONV.lsp" "wcalst.lsp"
                 "xftconv.lsp" "XYPLOT.lsp" "CONSTELLATION.lsp"
                 "LAZSPA.lsp"
                 "LAZFORM.lsp" "LAZPANEL.lsp")
      (cal--load m))
    (if (> cal:*missing* 0)
      (princ (strcat "\n[calofin] " (itoa cal:*missing*)
                     " file(s) missing - the build folder is incomplete."))
      (princ "\n[calofin] shared build loaded - every command in one session."))
    (if cal:*held-back*
      (princ (strcat "\n[calofin] " (itoa (length cal:*held-back*))
                     " file(s) held back - see cal:*held-back*.")))
    (princ "\n[calofin] Type CALVER for the library version.")))

(princ)
