;;; ===================================================================
;;; STOCKCOVER.lsp  -  paste a stock cover drawing onto a highlighted
;;;                    perimeter in the current drawing
;;;
;;; AutoCAD 2018+ (uses ActiveX for bounding boxes and the DWG insert
;;; fallback -- (vl-load-com) is called on load).
;;;
;;; Commands:
;;;   STOCKCOVER      replace a highlighted perimeter with a stock DWG
;;;   STOCKLIST       list every stock drawing in the stock folder
;;;   STOCKCOVER-CFG  point the routine at the stock folder
;;;
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;
;;; What STOCKCOVER does:
;;;   1. You highlight the perimeter that is to be replaced.
;;;   2. You type the short name of the stock drawing -- "5M" finds
;;;      "5M_Tech.dwg", "20M" finds "20M_Tech.dwg" (see the suffix
;;;      list below).  Enter on its own reuses the last name.
;;;   3. The stock DWG is read straight off disk into a scratch block,
;;;      exploded, and lined up on the highlighted perimeter so the two
;;;      perimeters sit on top of each other.
;;;   4. The highlighted entities are erased and the scratch block
;;;      definition is purged.
;;;
;;; Alignment is by the anchor POINTs both sides carry: the highlighted
;;; area and every stock drawing have a point at the bottom left and a
;;; point at the top right.  The stock is placed in ONE move, its
;;; bottom-left anchor onto the highlighted bottom-left anchor, and
;;; then left exactly there -- no fit prompt, no scaling, no shuffling
;;; afterwards.  When either side has no anchor points, the corners of
;;; its bounding box stand in and STOCKCOVER says so.  If the two
;;; anchor spans disagree by more than *stock-anchor-tol*, the wrong
;;; file was probably named: STOCKCOVER prints how far off it is, loud,
;;; but still places anchored -- one U rolls the whole run back.
;;; Nothing is erased until the new geometry is placed.
;;;
;;; The whole run is one UNDO step.
;;;
;;; Versioning: see tools/release_lisp.py at the repo root.  It reads
;;; *stockcover-version* below and stamps a dated, REV-numbered twin of
;;; this file into releases/.
;;; ===================================================================

(vl-load-com)

;;; -------------------------------------------------------------------
;;;  SETTINGS - set *stock-folder* before handing this file out; a user
;;;  can still override it per machine with STOCKCOVER-CFG, which is
;;;  remembered in the AutoCAD profile and wins over the value here.
;;; -------------------------------------------------------------------

(setq *stockcover-version* "v1.4") ; printed on load and at command
                                   ; start, so a loaded routine and its
                                   ; releases/ twin can never disagree

(setq *stock-folder* "F:\\TechTeam\\2022 StockCoverTech")
                                   ; where the stock DWGs live

(setq *stock-suffixes* '("_Tech"))  ; tried after an exact stem match:
                                    ; "5M" -> "5M.dwg", then
                                    ; "5M_Tech.dwg", then "5M*.dwg"

(setq *stock-explode* t)   ; T  = explode the insert so the stock
                           ;      geometry merges into the drawing
                           ; nil = leave it as a single block reference

(setq *stock-anchor-tol* 0.25) ; inches - the two anchor spans may
                            ; differ this much before STOCKCOVER
                            ; shouts that the wrong file was named

(setq *stock-env-folder* "StockCover_Folder") ; profile keys used to
(setq *stock-env-last*   "StockCover_Last")   ; remember folder + name

;;; -------------------------------------------------------------------
;;;  small helpers
;;; -------------------------------------------------------------------

(defun stock:say (s) (princ (strcat "\n" s)) (princ))

(defun stock:getenv (key / v)             ; "" and unset both read nil
  (setq v (getenv key))
  (if (and v (/= v "")) v))

(defun stock:fwd (s / i c out)            ; backslashes -> forward
  (setq out "" i 1)                       ; slashes, which AutoCAD's
  (while (<= i (strlen s))                ; file prompts prefer
    (setq c (substr s i 1))
    (setq out (strcat out (if (= c "\\") "/" c)))
    (setq i (1+ i)))
  out)

(defun stock:trim (s)                     ; drop a trailing separator
  (if (and (> (strlen s) 0)
           (member (substr s (strlen s) 1) '("\\" "/")))
    (substr s 1 (1- (strlen s)))
    s))

(defun stock:folder ()                    ; profile override, else the
  (stock:trim                             ; setting at the top of file
    (if (stock:getenv *stock-env-folder*)
      (stock:getenv *stock-env-folder*)
      *stock-folder*)))

(defun stock:path (folder file) (strcat folder "\\" file))

(defun stock:files (folder)               ; bare DWG names in folder
  (if (vl-file-directory-p folder)
    (vl-directory-files folder "*.dwg" 1)))

(defun stock:stems (files)
  (mapcar '(lambda (f) (vl-filename-base f)) files))

;;; Candidates for a typed name, best first: an exact stem match, then
;;; each configured suffix, then a leading-substring sweep.  Each rung
;;; is only tried when the one above it came up empty, so "5M" cannot
;;; be dragged off its exact file by "5MB_Tech.dwg" also existing.
(defun stock:match (name files / up hit f s)
  (setq up (strcase name))
  (foreach f files
    (if (= (strcase (vl-filename-base f)) up) (setq hit (cons f hit))))
  (if (null hit)
    (foreach s *stock-suffixes*
      (if (null hit)
        (foreach f files
          (if (= (strcase (vl-filename-base f)) (strcase (strcat name s)))
            (setq hit (cons f hit)))))))
  (if (null hit)
    (foreach f files
      (if (wcmatch (strcase (vl-filename-base f)) (strcat up "*"))
        (setq hit (cons f hit)))))
  (reverse hit))

(defun stock:uniq-block (/ i nm)          ; a block name the drawing is
  (setq i 0 nm "STOCK$0")                 ; not already using, so the
  (while (tblsearch "BLOCK" nm)           ; insert can never redefine
    (setq i (1+ i) nm (strcat "STOCK$" (itoa i))))
  nm)

;;; Everything added to the database after MARK (nil = whole drawing).
(defun stock:new-ents (mark / e ss)
  (setq ss (ssadd))
  (setq e (if mark (entnext mark) (entnext)))
  (while e
    (ssadd e ss)
    (setq e (entnext e)))
  (if (> (sslength ss) 0) ss))

;;; Combined bounding box of a selection set -> ((minx miny minz)
;;; (maxx maxy maxz)), or nil if nothing in it could be measured.
(defun stock:size (bb)                    ; (width height)
  (list (- (car (cadr bb)) (car (car bb)))
        (- (cadr (cadr bb)) (cadr (car bb)))))

(defun stock:fmt (wh)
  (strcat (rtos (car wh) 2 3) " x " (rtos (cadr wh) 2 3)))

;;; The bottom-left / top-right anchor POINTs of a selection: of all
;;; POINT entities in it, the ones lowest and highest along x+y.
;;; -> (bl tr) as 3D points, or nil when the selection holds fewer
;;; than two POINTs.
(defun stock:anchors (ss / i en ed p pts bl tr)
  (setq i 0)
  (while (< i (sslength ss))
    (setq en (ssname ss i)
          ed (entget en))
    (if (= (cdr (assoc 0 ed)) "POINT")
      (setq pts (cons (cdr (assoc 10 ed)) pts)))
    (setq i (1+ i)))
  (if (>= (length pts) 2)
    (progn
      (setq bl (car pts) tr (car pts))
      (foreach p (cdr pts)
        (if (< (+ (car p) (cadr p)) (+ (car bl) (cadr bl))) (setq bl p))
        (if (> (+ (car p) (cadr p)) (+ (car tr) (cadr tr))) (setq tr p)))
      (list (list (car bl) (cadr bl) 0.0)
            (list (car tr) (cadr tr) 0.0)))))

;;; Span of an anchor pair: (width height) bottom-left -> top-right.
(defun stock:span (an)
  (list (- (car (cadr an)) (car (car an)))
        (- (cadr (cadr an)) (cadr (car an)))))

;;; -------------------------------------------------------------------
;;;  reading the stock DWG in
;;; -------------------------------------------------------------------

;;; -INSERT with an explicit block name reads the file off disk rather
;;; than reusing anything already in the drawing.  2015+ engines refuse
;;; to route (command) through vl-catch-all-apply, so the insert goes
;;; through command-s, which runs the command to completion in one call
;;; and turns a failed insert into a catchable error instead of leaving
;;; the command hanging.  Each string travels as one input token, so the
;;; space in the stock folder's name needs no quoting.  If the insert
;;; still comes back empty, fall back to ActiveX, which takes the raw
;;; path.
(defun stock:insert (path bname / spec used stem)
  (setq spec (strcat bname "=" (stock:fwd path)))
  (vl-catch-all-apply
    'command-s (list "_.-INSERT" spec '(0.0 0.0 0.0) 1.0 1.0 0.0))
  (if (tblsearch "BLOCK" bname) (setq used bname))
  (if (null used)
    (progn
      ;; ActiveX takes the raw path, so it needs no quoting - but it
      ;; names the definition after the file, which can collide
      (setq stem (vl-filename-base path))
      (if (tblsearch "BLOCK" stem)
        (stock:say
          (strcat "a block named \"" stem "\" is already in this drawing -"
                  " rename it and try again."))
        (if (not (vl-catch-all-error-p
                   (vl-catch-all-apply 'vla-InsertBlock
                     (list (vla-get-ModelSpace
                             (vla-get-ActiveDocument (vlax-get-acad-object)))
                           (vlax-3d-point 0.0 0.0 0.0)
                           path 1.0 1.0 1.0 0.0))))
          (setq used stem)))))
  used)

;;; -------------------------------------------------------------------
;;;  STOCKLIST
;;; -------------------------------------------------------------------

(defun c:STOCKLIST (/ folder files s)
  (setq folder (stock:folder)
        files  (stock:files folder))
  (cond
    ((null (vl-file-directory-p folder))
     (stock:say (strcat "stock folder not reachable: " folder))
     (stock:say "point STOCKCOVER at it with STOCKCOVER-CFG."))
    ((null files)
     (stock:say (strcat "no DWGs in " folder)))
    (t
     (stock:say (strcat (itoa (length files)) " stock drawing(s) in " folder ":"))
     (foreach s (stock:stems files) (princ (strcat "\n  " s)))))
  (princ))

;;; -------------------------------------------------------------------
;;;  STOCKCOVER-CFG
;;; -------------------------------------------------------------------

(defun c:STOCKCOVER-CFG (/ cur f new)
  (setq cur (stock:folder))
  (stock:say (strcat "stock folder is now: " cur))
  ;; getfiled on any DWG inside the folder is the portable folder picker
  (setq f (getfiled "Pick any DWG inside the stock folder"
                    (strcat cur "\\") "dwg" 0))
  (if f
    (progn
      (setq new (stock:trim (vl-filename-directory f)))
      (setenv *stock-env-folder* new)
      (stock:say (strcat "stock folder set to " new))
      (stock:say (strcat (itoa (length (stock:files new))) " DWG(s) there.")))
    (stock:say "unchanged."))
  (princ))

;;; -------------------------------------------------------------------
;;;  STOCKCOVER
;;; -------------------------------------------------------------------

(defun c:STOCKCOVER (/ *error* stock:restore
                       oscm osos osclay osiu osareq osadia undone
                       folder files ss-old tbb tsz tanch name last hits
                       pick i file path bname mark ss-new sbb ssz sanch
                       dx dy f)

  (defun stock:restore ()
    (if oscm   (setvar "CMDECHO"  oscm))
    (if osos   (setvar "OSMODE"   osos))
    (if osclay (setvar "CLAYER"   osclay))
    (if osiu   (setvar "INSUNITS" osiu))
    (if osareq (setvar "ATTREQ"   osareq))
    (if osadia (setvar "ATTDIA"   osadia)))

  ;; 2015+ engines forbid (command) inside *error* unless the error
  ;; mode was pushed beforehand; command-s is the sanctioned
  ;; replacement and needs no setup, so the handler uses only that.
  (defun *error* (msg)
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nSTOCKCOVER error: " msg)))
    (stock:restore)
    (if undone
      (progn
        (vl-catch-all-apply 'command-s (list "_.UNDO" "_End"))
        (princ "\nNothing was left half done - use U to roll the run back.")))
    (princ))

  (setq oscm   (getvar "CMDECHO")
        osos   (getvar "OSMODE")
        osclay (getvar "CLAYER")
        osiu   (getvar "INSUNITS")
        osareq (getvar "ATTREQ")
        osadia (getvar "ATTDIA"))

  (stock:say (strcat "STOCKCOVER " *stockcover-version*
                     " - drop a stock cover onto a highlighted perimeter."))

  (setq folder (stock:folder))
  (setq files  (stock:files folder))
  (cond
    ((null (vl-file-directory-p folder))
     (stock:say (strcat "stock folder not reachable: " folder))
     (stock:say "set it with STOCKCOVER-CFG.")
     (setq files nil))
    ((null files)
     (stock:say (strcat "no DWGs in " folder))))

  (if files
    (progn
      ;; ---------------------------------------------- what to replace
      ;; a highlight made before the command was typed (pickfirst) is
      ;; the perimeter - only ask when there is none
      (setq ss-old (ssget "_I"))
      (if (null ss-old)
        (progn
          (princ "\nHighlight the perimeter to be replaced: ")
          (setq ss-old (ssget))))
      (if (null ss-old)
        (stock:say "nothing highlighted - nothing to replace.")
        (progn
          (setq tbb (cal:bbox-ss ss-old))
          (if (null tbb)
            (stock:say "could not measure the highlighted entities.")
            (progn
              (setq tsz (stock:size tbb))
              (stock:say (strcat "highlighted area: " (stock:fmt tsz)))
              (setq tanch (stock:anchors ss-old))
              (if tanch
                (stock:say "anchor points found on the highlighted area.")
                (progn
                  (setq tanch (list (car tbb) (cadr tbb)))
                  (stock:say "no anchor points highlighted - using the box corners.")))

              ;; ------------------------------------- which stock file
              (setq last (stock:getenv *stock-env-last*))
              (setq name
                (getstring t
                  (strcat "\nStock drawing name"
                          (if last (strcat " <" last ">") "") ": ")))
              (if (= name "") (setq name last))
              (if (null name)
                (stock:say "no name given.")
                (progn
                  (setq hits (stock:match name files))
                  (cond
                    ((null hits)
                     (stock:say (strcat "no stock drawing matches \"" name
                                        "\" - try STOCKLIST.")))
                    (t
                     (if (= (length hits) 1)
                       (setq file (car hits))
                       (progn
                         (stock:say (strcat (itoa (length hits))
                                            " drawings match \"" name "\":"))
                         (setq i 1)
                         (foreach f hits
                           (princ (strcat "\n  " (itoa i) ". "
                                          (vl-filename-base f)))
                           (setq i (1+ i)))
                         (initget 7)
                         (setq pick (getint "\nWhich one? "))
                         (setq file (if (and (>= pick 1) (<= pick (length hits)))
                                      (nth (1- pick) hits)))))
                     (if (null file)
                       (stock:say "no drawing picked.")
                       (progn
                         (setq path (stock:path folder file))
                         (setenv *stock-env-last* name)
                         (stock:say (strcat "using " path))

                         ;; ------------------------------- bring it in
                         (setvar "CMDECHO" 0)
                         (setvar "OSMODE" 0)
                         (setvar "INSUNITS" 0) ; no silent unit rescale
                         (setvar "ATTREQ" 0)
                         (setvar "ATTDIA" 0)
                         (command "_.UNDO" "_Begin")
                         (setq undone t)

                         (setq bname (stock:uniq-block))
                         (setq mark (entlast))
                         (setq bname (stock:insert path bname))
                         (if (null bname)
                           (stock:say (strcat "could not read " path))
                           (progn
                             (if *stock-explode*
                               (command "_.EXPLODE" (entlast) ""))
                             (setq ss-new (stock:new-ents mark))
                             (if (null ss-new)
                               (stock:say (strcat path " brought nothing in."))
                               (progn
                                 (setq sbb (cal:bbox-ss ss-new))
                                 (if (null sbb)
                                   (stock:say "could not measure the stock geometry.")
                                   (progn
                                     (setq ssz (stock:size sbb))
                                     (stock:say (strcat "stock geometry: "
                                                        (stock:fmt ssz)))

                                     ;; ------------------ anchor check
                                     (setq sanch (stock:anchors ss-new))
                                     (if (null sanch)
                                       (progn
                                         (setq sanch (list (car sbb) (cadr sbb)))
                                         (stock:say "no anchor points in the stock file - using its box corners.")))
                                     ;; the bottom-left -> top-right
                                     ;; spans should agree; when they do
                                     ;; not, the wrong file was probably
                                     ;; named - say so, loudly, but the
                                     ;; placement stays anchored as-is
                                     (setq dx (- (car (stock:span sanch))
                                                 (car (stock:span tanch)))
                                           dy (- (cadr (stock:span sanch))
                                                 (cadr (stock:span tanch))))
                                     (if (or (> (abs dx) *stock-anchor-tol*)
                                             (> (abs dy) *stock-anchor-tol*))
                                       (progn
                                         (stock:say (strcat "ANCHORS DO NOT AGREE: the stock's span is off by "
                                                            (rtos dx 2 3) " across and "
                                                            (rtos dy 2 3) " up."))
                                         (stock:say "check you named the right stock drawing - one U rolls this back.")))

                                     ;; ------------------------- place:
                                     ;; ONE move, bottom-left anchor to
                                     ;; bottom-left anchor, and it stays
                                     ;; exactly there
                                     (command "_.MOVE" ss-new ""
                                              (car sanch) (car tanch))
                                     (command "_.ERASE" ss-old "")
                                     (if *stock-explode*
                                       (command "_.-PURGE" "_B" bname "_N"))
                                     (stock:say
                                       (strcat (vl-filename-base file) " placed on the anchor - "
                                               (itoa (sslength ss-new))
                                               " object(s) in, "
                                               (itoa (sslength ss-old))
                                               " out."))))))))
                         (command "_.UNDO" "_End")
                         (setq undone nil)))))))))))))

  (stock:restore)
  (princ))

(princ (strcat "\nSTOCKCOVER " *stockcover-version*
               " loaded.  STOCKCOVER to place a stock cover,"
               " STOCKLIST to see what is available,"
               " STOCKCOVER-CFG to set the folder."))
(princ)
