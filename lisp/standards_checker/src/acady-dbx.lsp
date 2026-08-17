;;; acady-dbx.lsp
;;; ObjectDBX access — the portability boundary (AutoCAD 2018 / BricsCAD).
;;; Exposes:
;;;   (acady-dbx-available-p)          probe once, memoized
;;;   (acady-dbx-with-doc path fn)     fn receives a ModelSpace-like collection;
;;;                                    open/release handled here, editor-open
;;;                                    files served from the Documents collection.
;;; Rules enforced here: fresh AxDbDocument per file, never (command) while a
;;; DBX doc is live, always release, a bad file never aborts the caller.

(setq *acady-dbx-progid* nil) ; memoized winning ProgID

(defun acady-dbx--candidates (/ ver out)
  ;; version-matched first, then bare, then a sweep of majors
  (setq ver (itoa (fix (atof (getvar "ACADVER"))))) ; 2018 -> "22"
  (setq out (list (strcat "ObjectDBX.AxDbDocument." ver)
                  "ObjectDBX.AxDbDocument"))
  (foreach v '("25" "24" "23" "22" "21" "20" "19" "18" "17" "16")
    (if (not (member (strcat "ObjectDBX.AxDbDocument." v) out))
      (setq out (append out (list (strcat "ObjectDBX.AxDbDocument." v))))))
  out)

(defun acady-dbx--probe (/ acad dbx)
  (setq acad (vlax-get-acad-object))
  (foreach pid (acady-dbx--candidates)
    (if (null *acady-dbx-progid*)
      (progn
        (setq dbx (acady-catch 'vla-GetInterfaceObject (list acad pid)))
        (if dbx
          (progn
            (setq *acady-dbx-progid* pid)
            (acady-release dbx)
            (acady-dbg (strcat "ObjectDBX ProgID: " pid)))))))
  *acady-dbx-progid*)

(defun acady-dbx-available-p ()
  (if *acady-dbx-progid* t (if (acady-dbx--probe) t nil)))

(defun acady-dbx--editor-doc (path / acad docs found item full)
  ;; if path is open in the editor, return that Document (do NOT release it)
  (setq acad (vlax-get-acad-object)
        docs (acady-catch 'vla-get-Documents (list acad))
        path (strcase path)
        found nil)
  (if docs
    (vlax-for item docs
      (if (null found)
        (progn
          (setq full (acady-catch 'vla-get-FullName (list item)))
          (if (and full (= (strcase full) path))
            (setq found item))))))
  found)

(defun acady-dbx-with-doc (path fn / acad edoc dbx opened ms result err)
  ;; call (fn modelspace) for the drawing at path.
  ;; returns (list T result) on success, (list nil errmsg) on failure.
  (setq path (findfile path))
  (cond
    ((null path) (list nil "file not found"))
    ((setq edoc (acady-dbx--editor-doc path))
     ;; open in the editor: use its live model space, no DBX, no release
     (setq ms (acady-catch 'vla-get-ModelSpace (list edoc)))
     (if ms
       (progn
         (setq result (vl-catch-all-apply fn (list ms)))
         (if (vl-catch-all-error-p result)
           (list nil (vl-catch-all-error-message result))
           (list t result)))
       (list nil "could not read editor document")))
    ((not (acady-dbx-available-p))
     (list nil "ObjectDBX is not available on this system"))
    (t
     (setq acad (vlax-get-acad-object))
     ;; fresh AxDbDocument per file — reuse across Opens is undefined behavior
     (setq dbx (acady-catch 'vla-GetInterfaceObject (list acad *acady-dbx-progid*)))
     (if (null dbx)
       (list nil (strcat "could not create AxDbDocument: "
                         (if *acady-last-err* *acady-last-err* "?")))
       (progn
         (setq opened (acady-catch 'vla-Open (list dbx path)))
         (setq err *acady-last-err*)
         (if (and (null opened) err)
           (progn
             (acady-release dbx)
             (list nil (strcat "open failed: " err)))
           (progn
             (setq ms (acady-catch 'vla-get-ModelSpace (list dbx)))
             (setq result
               (if ms
                 (vl-catch-all-apply fn (list ms))
                 nil))
             (acady-release dbx) ; always, before reporting
             (cond
               ((null ms) (list nil "no model space in file"))
               ((vl-catch-all-error-p result)
                (list nil (vl-catch-all-error-message result)))
               (t (list t result))))))))))

(defun acady-dbx-folder-files (folder / files)
  ;; full paths of all DWGs in folder (vl-directory-files gives bare names;
  ;; findfile doesn't search arbitrary folders, so join manually)
  (setq files (vl-directory-files folder "*.dwg" 1))
  (mapcar '(lambda (f) (strcat folder "\\" f))
          (if files files nil)))

(princ "\n[acady] dbx loaded.")
(princ)
