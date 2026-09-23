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

(setq *stockcover-version* "v1.10") ; printed on load and at command
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
(defun stock:bbox (ss / i obj ll ur p1 p2 mn mx)
  (setq i 0)
  (while (< i (sslength ss))
    (setq obj (vlax-ename->vla-object (ssname ss i)))
    (if (not (vl-catch-all-error-p
               (vl-catch-all-apply 'vla-GetBoundingBox (list obj 'll 'ur))))
      (progn
        (setq p1 (vlax-safearray->list ll)
              p2 (vlax-safearray->list ur))
        (setq mn (if mn (mapcar 'min mn p1) p1)
              mx (if mx (mapcar 'max mx p2) p2))))
    (setq i (1+ i)))
  (if (and mn mx) (list mn mx)))

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
;;;  locked layers, and checking the swap really happened
;;; -------------------------------------------------------------------

;;; ERASE and MOVE pass over anything on a locked layer without a word
;;; under CMDECHO 0, and -INSERT still lands on a locked current layer
;;; that EXPLODE and MOVE then refuse.  A locked POOL layer left the old
;;; perimeter under the new cover while the done line counted it "out";
;;; a locked current layer left the cover at 0,0 and the perimeter gone.
(defun stock:locked-p (lname / tb)
  (and lname
       (setq tb (tblsearch "LAYER" lname))
       (= 4 (logand 4 (cdr (assoc 70 tb))))))

;;; Every locked layer SS sits on, each named once.  The selection is
;;; walked rather than the table: a locked layer nothing highlighted
;;; sits on cannot get in the way.
(defun stock:locked-layers (ss / i lay seen out)
  (setq i 0)
  (while (< i (sslength ss))
    (setq lay (cdr (assoc 8 (entget (ssname ss i)))))
    (if (and lay (not (member (strcase lay) seen)))
      (progn
        (setq seen (cons (strcase lay) seen))
        (if (stock:locked-p lay) (setq out (cons lay out)))))
    (setq i (1+ i)))
  (reverse out))

;;; What stops the swap before it starts: the locked layers the
;;; highlight sits on, plus a locked current layer, which the insert
;;; lands on.
(defun stock:in-the-way (ss / out cl)
  (setq out (stock:locked-layers ss)
        cl  (getvar "CLAYER"))
  (if (and (stock:locked-p cl)
           (not (member (strcase cl) (mapcar 'strcase out))))
    (setq out (append out (list cl))))
  out)

(defun stock:names (lst / out s)          ; ("A" "B") -> "A, B"
  (foreach s lst
    (setq out (if out (strcat out ", " s) s)))
  out)

;;; How many of SS are really gone from the drawing -- the count the
;;; done line reports, rather than the size of the set handed to ERASE.
(defun stock:gone (ss / i n)
  (setq i 0 n 0)
  (while (< i (sslength ss))
    (if (null (entget (ssname ss i))) (setq n (1+ n)))
    (setq i (1+ i)))
  n)

;;; T when box NBB is box OBB shifted by D, in plan: the proof the MOVE
;;; took every piece, since a piece MOVE skipped stays where it was and
;;; drags the box with it.
(defun stock:shifted-p (obb nbb d)
  (and nbb
       (equal (list (+ (car (car obb)) (car d)) (+ (cadr (car obb)) (cadr d))
                    (+ (car (cadr obb)) (car d)) (+ (cadr (cadr obb)) (cadr d)))
              (list (car (car nbb)) (cadr (car nbb))
                    (car (cadr nbb)) (cadr (cadr nbb)))
              1e-4)))

;;; The stock squared to the World axes, whatever the UCS.  -INSERT
;;; reads its 0.0 rotation in the current UCS, and through ANGBASE as
;;; well, so under a UCS turned to follow the pool the stock came in
;;; turned by the same angle, its anchor span stopped matching, and the
;;; drafter was told they had named the wrong stock drawing.  Where it
;;; landed does not matter -- the anchors are measured after this --
;;; so only the turn is undone, as a World-axis ActiveX transform that
;;; carries any attributes along with the reference.
(defun stock:square (e / ed rot nrm)
  (setq ed  (if e (entget e))
        rot (cdr (assoc 50 ed))
        nrm (cdr (assoc 210 ed)))
  (if (and (= "INSERT" (cdr (assoc 0 ed)))
           rot
           (not (equal rot 0.0 1e-12))
           (or (null nrm) (equal nrm '(0.0 0.0 1.0) 1e-9)))
    (vla-Rotate (vlax-ename->vla-object e)
                (vlax-3d-point (cdr (assoc 10 ed)))
                (- rot))))

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

(defun c:STOCKCOVER-CFG ( / *error* cur f new)
  ;; Nothing to put back -- this command opens no undo group and
  ;; changes no system variable -- but a failure still has to be SAID,
  ;; and said to LAZDIAG, or it is the one command in the build whose
  ;; bugs arrive as a bare AutoCAD message with no report behind them.
  (defun *error* (msg)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nSTOCKCOVER-CFG error: " msg)))
    (if lzd:report (lzd:report "STOCKCOVER-CFG" *stockcover-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "STOCKCOVER-CFG" *stockcover-version*))
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
  (if lzd:end (lzd:end "STOCKCOVER-CFG"))
  (princ))

;;; -------------------------------------------------------------------
;;;  STOCKCOVER
;;; -------------------------------------------------------------------

(defun c:STOCKCOVER (/ *error* stock:restore
                       oscm osos osclay osiu osareq osadia undone
                       folder files ss-old tbb tsz tanch name last hits
                       pick i file path bname mark ss-new sbb ssz sanch
                       dx dy f locked stuck out)

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
    (if lzd:report (lzd:report "STOCKCOVER" *stockcover-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "STOCKCOVER" *stockcover-version*))

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
      (if lzd:watch (lzd:watch ss-old) ss-old)
      (if (null ss-old)
        (progn
          (princ "\nHighlight the perimeter to be replaced: ")
          (setq ss-old (ssget))
          (if lzd:watch (lzd:watch ss-old) ss-old)))
      (cond
        ((null ss-old)
         (stock:say "nothing highlighted - nothing to replace."))
        ;; refused before anything is inserted, with the layers named:
        ;; the commands below would pass over them without a word
        ((setq locked (stock:in-the-way ss-old))
         (stock:say (strcat "Unlock " (stock:names locked)
                            " first, then run STOCKCOVER again.")))
        (t
          (setq tbb (stock:bbox ss-old))
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
              ;; the name and the which-one pick are one chain: Back at
              ;; the pick re-asks the name, so a search that turned up
              ;; the wrong dozen costs one keystroke instead of the
              ;; whole command.
              (setq last (stock:getenv *stock-env-last*)
                    pick 'RETRY)
              (while (eq pick 'RETRY)
                (setq pick nil
                      file nil)
                (setq name
                  (getstring t
                    (strcat "\nStock drawing name"
                            (if last (strcat " <" last ">") "") ": ")))
                (if lzd:ask (lzd:ask (getvar "LASTPROMPT") name) name)
                (if (= name "") (setq name last))
                (if (null name)
                  (stock:say "no name given.")
                  (progn
                    (setq hits (stock:match name files))
                    (cond
                      ((null hits)
                       (stock:say (strcat "no stock drawing matches \"" name
                                          "\" - try STOCKLIST.")))
                      ((= (length hits) 1) (setq file (car hits)))
                      (t
                       (stock:say (strcat (itoa (length hits))
                                          " drawings match \"" name "\":"))
                       (setq i 1)
                       (foreach f hits
                         (princ (strcat "\n  " (itoa i) ". "
                                        (vl-filename-base f)))
                         (setq i (1+ i)))
                       (initget 7 "Back Undo")
                       (setq pick (getint "\nWhich one? [Back]: "))
                       (if lzd:ask (lzd:ask "\nWhich one? [Back]: " pick) pick)
                       (if (and (= (type pick) 'STR)
                                (member pick '("Back" "Undo")))
                         (progn (stock:say "stepping back one question.")
                                (setq pick 'RETRY))
                         (setq file (if (and (>= pick 1)
                                             (<= pick (length hits)))
                                      (nth (1- pick) hits)))))))))
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
                  ;; only when undo is recording - _Begin in a drawing with UNDO
                  ;; off (bit 1 of UNDOCTL clear) errors out of the command
                  (if (= 1 (logand 1 (getvar "UNDOCTL")))
                    (progn
                      (command "_.UNDO" "_Begin")
                      (setq undone t)))

                  (setq bname (stock:uniq-block))
                  (setq mark (entlast))
                  (setq bname (stock:insert path bname))
                  (if (null bname)
                    (stock:say (strcat "could not read " path))
                    (progn
                      ;; Only a reference this insert placed is turned
                      ;; or exploded.  -INSERT can define the block and
                      ;; still place nothing, and then entlast is the
                      ;; drafter's own last object: a rotated block of
                      ;; theirs was squared to 0 and blown apart, and
                      ;; STOCKCOVER went on to say the stock brought
                      ;; nothing in.
                      (if (not (eq (entlast) mark))
                        (progn
                          (stock:square (entlast))
                          (if *stock-explode*
                            (command "_.EXPLODE" (entlast) ""))))
                      (setq ss-new (stock:new-ents mark))
                      (if (null ss-new)
                        (stock:say (strcat path " brought nothing in."))
                        (progn
                          (setq sbb (stock:bbox ss-new))
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
                              ;; exactly there.  The anchors are World
                              ;; points and MOVE reads the UCS, so both
                              ;; go through trans: a turned UCS turned
                              ;; the displacement with it.
                              (command "_.MOVE" ss-new ""
                                       (trans (car sanch) 0 1)
                                       (trans (car tanch) 0 1))
                              (if *stock-explode*
                                (command "_.-PURGE" "_B" bname "_N"))
                              ;; the old perimeter goes only once the
                              ;; new one is proven on the anchor: a
                              ;; stock piece landing on a locked layer
                              ;; of the same name is one MOVE skips
                              (setq stuck (stock:locked-layers ss-new))
                              (if (or stuck
                                      (not (stock:shifted-p
                                             sbb (stock:bbox ss-new)
                                             (mapcar '- (car tanch) (car sanch)))))
                                (progn
                                  (stock:say
                                    (strcat "the stock did NOT all move onto the anchor"
                                            (if stuck
                                              (strcat " - pieces are on locked layer(s) "
                                                      (stock:names stuck))
                                              "")
                                            "."))
                                  (stock:say "the old perimeter was left in place - one U rolls this back."))
                                (progn
                                  (command "_.ERASE" ss-old "")
                                  (setq out (stock:gone ss-old))
                                  (stock:say
                                    (strcat (vl-filename-base file) " placed on the anchor - "
                                            (itoa (sslength ss-new))
                                            " object(s) in, "
                                            (itoa out)
                                            " out."))
                                  (if (< out (sslength ss-old))
                                    (stock:say
                                      (strcat (itoa (- (sslength ss-old) out))
                                              " highlighted object(s) could NOT be erased"
                                              " - they are still under the new cover.")))))))))))
                  ;; closed only if one was opened, as the handler
                  ;; above is: with undo recording off (UNDOCTL bit 1
                  ;; clear) there is none, and an _End on nothing is an
                  ;; error of its own -- here, with the cover already
                  ;; placed on the anchor
                  (if undone
                    (progn
                      (command "_.UNDO" "_End")
                      (setq undone nil)))))))))))

  (stock:restore)
  (if lzd:end (lzd:end "STOCKCOVER"))
  (princ))

;; Which build is loaded - the first thing to check when a run does
;; something the notes above say it should not.
(defun c:STOCKCOVERVER ()
  (princ (strcat "\nSTOCKCOVER " *stockcover-version*))
  (princ))

;; Quiet inside the whole build: LAZPASS.lsp and
;; CALOFIN-LOADER.lsp set the flag while they load their members,
;; because one file's greeting is a greeting and sixty-three of
;; them is a wall the drafter scrolls past in every drawing they
;; open.  APPLOADed alone the flag is nil and this prints, which
;; is the one time somebody wants to be told.  CALVER reports the
;; whole roster whenever it is asked.
(if (not *calofin-quiet*)
  (princ (strcat "\nSTOCKCOVER " *stockcover-version*
                 " loaded.  STOCKCOVER to place a stock cover,"
                 " STOCKLIST to see what is available,"
                 " STOCKCOVER-CFG to set the folder.")))
(princ)
