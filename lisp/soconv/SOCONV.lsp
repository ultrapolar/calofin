;;; ======================================================================
;;; SOCONV.lsp  --  put an SO site-survey export onto the shop's layers
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  SOCONV     move the import onto POOL / POINTS / TEXT /
;;;                       DIMENSION
;;;            SOCONVVER  print the loaded version
;;; ======================================================================
;;;
;;; The survey arrives on the export's own layer names and has to be on
;;; the shop's before the rest of the build can work on it: ABHD and
;;; POINTRENAMER read the survey points off POINTS, LINGUTTER draws its
;;; perimeter on POOL, and AUTODIM and CUSTBLOCK dimension onto
;;; DIMENSION.  The whole move is the handful of rules below, read off
;;; the before/after sample the shop supplied (SOconv.dxf -- 316 objects
;;; converted by hand, kept beside the original in the one drawing):
;;;
;;;   from the export             what is on it     onto
;;;   -------------------------   ---------------   ---------
;;;   Pool Perimeter              everything        POOL
;;;   Obstacles                   everything        POOL
;;;   LEICA_DISTO_POINT_ENTITY    POINT             POINTS
;;;   Existing Anchorss           POINT             POINTS
;;;   Dimensions                  TEXT, MTEXT       TEXT
;;;   Dimensions                  everything else   DIMENSION
;;;
;;; THE OBSTACLES REALLY DO GO ONTO POOL.  They are drawn as part of
;;; the same outline once the survey is in the shop's drawing, and the
;;; sample moves all twelve of them there.
;;;
;;; NOTHING ELSE ABOUT AN ENTITY CHANGES.  This is a layer remap and
;;; only a layer remap: the colour, linetype, lineweight, height,
;;; style, rotation and text an object arrived with are the ones it
;;; keeps.  That is what the sample shows rather than what a cleanup
;;; would do -- the 161 Leica points carry an explicit magenta into the
;;; conversion and still carry it out the other side, and the notes
;;; (Up 6", Planter, Existing Anchors) land on TEXT at the height and
;;; style they came in at.  DRONE and TYDRN restyle; SOCONV does not, and
;;; *soconv-force-bylayer* below is the one line that changes its mind.
;;;
;;; NOTHING IS ERASED OR DRAWN either.  (The sample's after side is one
;;; dimension short of its before side -- the drafter dropped a linear
;;; dim by hand while making it.  That is an edit, not a rule, and it
;;; is not in here.)
;;;
;;; Locked layers among those touched are unlocked for the run and
;;; re-locked afterwards, on the error path too; the destination layers
;;; are created if the drawing does not have them, and thawed and
;;; switched on if it does.  The whole run is one undo group.
;;; ======================================================================

(setq *soconv-version* "v1.0")   ; announced on load; release_lisp.py
                                 ; stamps the dated twin in releases/

(vl-load-com)

;; ---------------------------------------------------------------
;; Configuration
;; ---------------------------------------------------------------

;; The conversion itself, one row per rule:
;;
;;     (source-layer  entity-types  destination-layer)
;;
;; Both patterns are wcmatch patterns -- "," is alternation, "*" is
;; anything -- and the rows are tried IN ORDER, the first match
;; winning.  That ordering is what lets the two Dimensions rows split
;; the export's one layer into two of ours: the notes are caught by the
;; TEXT,MTEXT row above, so the catch-all below it takes the dimensions
;; and anything else the export chose to leave there (a leader, a
;; witness line -- the sample had neither).
;;
;; "Existing Anchorss" is spelled the way the export spells it, doubled
;; s and all.  The correct spelling is listed after it so a fixed
;; export keeps working.
(setq *soconv-map*
  '(("Pool Perimeter"           "*"          "POOL")
    ("Obstacles"                "*"          "POOL")
    ("LEICA_DISTO_POINT_ENTITY" "POINT"      "POINTS")
    ("Existing Anchorss"        "POINT"      "POINTS")
    ("Existing Anchors"         "POINT"      "POINTS")
    ("Dimensions"               "TEXT,MTEXT" "TEXT")
    ("Dimensions"               "*"          "DIMENSION")))

;; What to CREATE a destination layer with when the drawing has not got
;; it.  An existing layer is never recoloured -- the shop template's
;; own POOL, POINTS, TEXT and DIMENSION are what a converted drawing
;; keeps, whatever is listed here -- so these only ever show on a bare
;; drawing.  POOL is cyan to agree with POOL.LSP and POOLSIDE, which
;; are the other two places in the build that create it.
(setq *soconv-colors*
  '(("POOL"      . 4)      ; cyan, as POOL.LSP creates it
    ("POINTS"    . 6)      ; magenta - the pink survey points read as
    ("TEXT"      . 4)
    ("DIMENSION" . 141)))

(setq *soconv-default-color* 7)   ; a destination not named above

;; nil, and a moved object keeps every property it arrived with, which
;; is what the sample conversion does.  T instead forces colour,
;; linetype and lineweight to BYLAYER on the way past, the way DRONE
;; and TYDRN do -- so the import takes the destination layer's own
;; appearance and nothing overrides it later.
(setq *soconv-force-bylayer* nil)

;; ---------------------------------------------------------------
;; Helpers
;; ---------------------------------------------------------------

;; Make sure the target layer exists.
(defun soconv:ensure-layer (name color / rec ed flags col fixed)
  (if (not (tblsearch "LAYER" name))
    (entmakex (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                    '(100 . "AcDbLayerTableRecord")
                    (cons 2 name) '(70 . 0) (cons 62 color)
                    '(6 . "Continuous")))
    (progn
      (setq rec   (tblobjname "LAYER" name)
            ed    (entget rec)
            flags (cdr (assoc 70 ed))
            col   (cdr (assoc 62 ed))
            fixed nil)
      (if (/= 0 (logand 5 flags))          ; frozen (1) or locked (4)
        (setq ed    (subst (cons 70 (- flags (logand 5 flags)))
                           (assoc 70 ed) ed)
              fixed T))
      (if (< col 0)                        ; layer switched off
        (setq ed    (subst (cons 62 (abs col)) (assoc 62 ed) ed)
              fixed T))
      (if fixed
        (progn
          (entmod ed)
          (princ (strcat "\nLayer " name
                         " was off, frozen or locked - restored so the"
                         " result is visible."))))))
  name)

;; Unlock every layer in NAMES that is currently locked and return the
;; list of layer objects that were unlocked (so they can be re-locked).
(defun soconv:unlock-layers (names doc / layers obj unlocked name)
  (setq layers (vla-get-Layers doc))
  (foreach name names
    (if (and name (tblsearch "LAYER" name))
      (progn
        (setq obj (vla-Item layers name))
        (if (= :vlax-true (vla-get-Lock obj))
          (progn
            (vla-put-Lock obj :vlax-false)
            (setq unlocked (cons obj unlocked)))))))
  unlocked)

(defun soconv:relock-layers (objs / obj)
  (foreach obj objs (vla-put-Lock obj :vlax-true)))

;; Reset color / linetype / lineweight of a vla-object to BYLAYER.
;; Only reached with *soconv-force-bylayer* on.
(defun soconv:force-bylayer (obj)
  (vla-put-Color obj acByLayer)
  (vla-put-Linetype obj "ByLayer")
  (vla-put-Lineweight obj acLnWtByLayer))

;; NAME added to LST unless a spelling of it is in there already; the
;; order is first-seen, which is the order the report reads in.
(defun soconv:add (name lst)
  (if (member (strcase name) (mapcar 'strcase lst))
    lst
    (append lst (list name))))

;; The destination for an entity of type TYP on layer LAY, or nil when
;; no rule claims it.  Rows are tried in order and the first wins.
(defun soconv:dest (typ lay / rule out)
  (foreach rule *soconv-map*
    (if (and (null out)
             (wcmatch (strcase lay) (strcase (car rule)))
             (wcmatch (strcase typ) (strcase (cadr rule))))
      (setq out (caddr rule))))
  out)

;; DEST's count in TALLY, up by one -- appended when it is new, so the
;; tally stays in the order the destinations were first reached.
(defun soconv:bump (dest tally / p)
  (if (setq p (assoc dest tally))
    (subst (cons dest (1+ (cdr p))) p tally)
    (append tally (list (cons dest 1)))))

;; The source layers the map names, for the message that gets printed
;; when a drawing has none of them.
(defun soconv:sources ( / rule out)
  (foreach rule *soconv-map*
    (setq out (soconv:add (car rule) out)))
  out)

;; The colour to CREATE destination NAME with (see *soconv-colors*).
(defun soconv:color (name / rule out)
  (foreach rule *soconv-colors*
    (if (and (null out) (= (strcase (car rule)) (strcase name)))
      (setq out (cdr rule))))
  (if out out *soconv-default-color*))

;; "Dimensions, Obstacles, Pool Perimeter"
(defun soconv:namelist (names / out name)
  (foreach name names
    (setq out (strcat (if out (strcat out ", ") "") name)))
  out)

;; "69 -> POOL, 232 -> POINTS"
(defun soconv:tally-line (tally / out p)
  (foreach p tally
    (setq out (strcat (if out (strcat out ", ") "")
                      (itoa (cdr p)) " -> " (car p))))
  out)

;; Work out what moves where WITHOUT touching anything, so the run can
;; ask for exactly the layers it needs and can say up front that a
;; drawing has nothing to convert.  Returns
;;
;;     (jobs source-layers destination-layers tally)
;;
;; where jobs is a list of (ename . destination) in drawing order.  An
;; object a rule sends to the layer it is already on is not a job.
(defun soconv:plan (ss / i ent ed typ lay dest jobs srcs dests tally)
  (setq i 0)
  (while (< i (sslength ss))
    (setq ent  (ssname ss i)
          ed   (entget ent)
          typ  (cdr (assoc 0 ed))
          lay  (cdr (assoc 8 ed))
          dest (soconv:dest typ lay))
    (if (and dest (/= (strcase lay) (strcase dest)))
      (setq jobs  (cons (cons ent dest) jobs)
            srcs  (soconv:add lay srcs)
            dests (soconv:add dest dests)
            tally (soconv:bump dest tally)))
    (setq i (1+ i)))
  (list (reverse jobs) srcs dests tally))

;; ---------------------------------------------------------------
;; Main command
;; ---------------------------------------------------------------
(defun c:SOCONV (/ *error* doc unlocked mark-open ss plan jobs srcs dests
                   tally job dest obj)

  ;; The handler is LOCAL to this command (STANDARDS 5): a handler
  ;; installed in the global *error* is the handler of whatever runs
  ;; next the first time a run ends without putting it back.  It sees
  ;; doc / unlocked / mark-open through dynamic scope, and closes only
  ;; the mark this run opened -- the close can itself throw when the
  ;; failure came before StartUndoMark, and a throw inside *error* is
  ;; the one error nothing can catch.
  (defun *error* (msg)
    ;; locked layers come back FIRST so nothing below can skip them
    (if unlocked (vl-catch-all-apply 'soconv:relock-layers (list unlocked)))
    (setq unlocked nil)
    (if mark-open (vl-catch-all-apply 'vla-EndUndoMark (list doc)))
    (setq mark-open nil)
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nSOCONV error: " msg)))
    (princ))

  (setq doc      (vla-get-ActiveDocument (vlax-get-acad-object))
        unlocked nil)

  (vla-StartUndoMark doc)
  (setq mark-open T)

  ;; What to convert: the highlight if there is one, else what is
  ;; picked at the prompt, else the whole drawing.  An import usually
  ;; IS the whole drawing, which is why Enter means that; highlight
  ;; first when two surveys share one drawing.
  (setq ss (ssget "_I"))
  (if (null ss)
    (progn
      (prompt "\nSelect the survey import to convert <Enter = whole drawing>: ")
      (setq ss (ssget))
      (if (null ss)
        (setq ss (ssget "_X")))))

  (setq plan  (if ss (soconv:plan ss) '(nil nil nil nil))
        jobs  (car plan)
        srcs  (cadr plan)
        dests (caddr plan)
        tally (cadddr plan))

  (if jobs
    (progn
      ;; only the destinations this run actually reaches -- a drawing
      ;; with no dimensions in its survey does not want an empty
      ;; DIMENSION layer created for it
      (foreach dest dests
        (soconv:ensure-layer dest (soconv:color dest)))
      ;; unlock everything about to be touched, both ends of the move
      (setq unlocked (soconv:unlock-layers (append srcs dests) doc))
      (foreach job jobs
        (setq obj (vlax-ename->vla-object (car job)))
        (vla-put-Layer obj (cdr job))
        (if *soconv-force-bylayer*
          (soconv:force-bylayer obj)))
      (soconv:relock-layers unlocked)
      (setq unlocked nil)))

  (vla-EndUndoMark doc)
  (setq mark-open nil)

  (if jobs
    (progn
      (princ (strcat "\nSOCONV done: " (itoa (length jobs))
                     " object(s) moved -- " (soconv:tally-line tally) "."))
      (princ (strcat "\n  Moved off " (soconv:namelist srcs)
                     " - PURGE those layers once the result looks right.")))
    (progn
      (princ "\nSOCONV: nothing here is on the export's layers - nothing moved.")
      (princ (strcat "\n  It converts " (soconv:namelist (soconv:sources))
                     "."))))
  (princ))

(defun c:SOCONVVER ()
  (princ (strcat "\nSOCONV " *soconv-version*))
  (princ))

(princ (strcat "\nSOCONV " *soconv-version* " loaded.  Type SOCONV to run."))
(princ)
