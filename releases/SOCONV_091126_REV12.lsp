;;; ======================================================================
;;; SOCONV.lsp  --  put an SO site-survey export onto the shop's layers
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  SOCONV     move the import onto POOL / POINTS / TEXT /
;;;                       DIMENSION
;;;            SORECONV   put a converted import back on the export's
;;;                       own layers
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
;;; A locked SOURCE layer is unlocked for the run and re-locked
;;; afterwards, on the error path too.  The destination layers are
;;; output layers: only the ones the selection actually reaches are
;;; created, and one that exists but is frozen, locked or off is
;;; repaired for good, with a line saying so (STANDARDS 5).  The whole
;;; run is one undo group.
;;;
;;; SORECONV MOVES IT ALL BACK.  U undoes a run still in the session;
;;; SORECONV undoes one that was saved and reopened, which is when a
;;; drawing turns out to have been converted by mistake or to need
;;; sending back to whoever exported it.  Every object SOCONV moves
;;; carries a RECORD in its own xdata -- the layer it came off, that
;;; layer's colour, and (only when *soconv-force-bylayer* was on) the
;;; colour, linetype and lineweight the forcing overwrote.  SORECONV
;;; reads it, puts the object back, re-creates a source layer that has
;;; been PURGED in the meantime, and takes the record off again.
;;;
;;; The record is xdata under "SOCONV" and nothing else about the
;;; object changes, so a converted drawing still looks and plots
;;; exactly as it did before the record existed.
;;;
;;; ONE THING THE REVERT SPELLS OUT rather than restores: with the
;;; forcing on, an object that arrived carrying NO colour, linetype or
;;; lineweight of its own comes back carrying an explicit ByLayer --
;;; 256, "ByLayer", -1 -- where it had the absent group that means the
;;; same thing.  It draws and plots identically, and a DXF diff of the
;;; before and after says so; nothing else about the round trip is
;;; approximate.
;;; ======================================================================

(setq *soconv-version* "v1.2")   ; announced on load; release_lisp.py
                                 ; stamps the dated twin in releases/

(vl-load-com)

;;; -------------------- tunables ----------------------------------------
;;; Everything a shop might want changed, all in one block; nothing
;;; settable lives anywhere else in this file.  Each says what CHANGING
;;; it does.  setq any of them after loading -- in a startup file, say
;;; -- and the next run reads the new value.

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

;; The colour for a destination the table above does not name - what a
;; retuned *soconv-map* row pointing at a new layer gets.  7 is white.
(setq *soconv-default-color* 7)

;; nil, and a moved object keeps every property it arrived with, which
;; is what the sample conversion does.  T instead forces colour,
;; linetype and lineweight to BYLAYER on the way past, the way DRONE,
;; TYDRN and VSCONV do -- so the import takes the destination layer's
;; own appearance and nothing overrides it later.  VSCONV carries the
;; same switch with the opposite default, because ITS sample restyles.
(setq *soconv-force-bylayer* nil)

;; The record SORECONV reads back, and the application it lives under.
;; nil converts exactly as before and writes nothing down, so the run
;; can only be undone by U; the tests drive both ways.
(setq *soconv-record*     t
      *soconv-xdata-app*  "SOCONV")

;;; -------------------- helpers -----------------------------------------

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

;; The layer ENT is on right now.
(defun soconv:layer-of (ent)
  (cdr (assoc 8 (entget ent))))

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

;;; -------------------- the record --------------------------------------
;; Eight xdata items in a fixed order, which is why there is no
;; grammar here to get wrong: xdata groups are typed, so a layer name
;; carrying a "|" (an xref-dependent one does) or a linetype called
;; anything at all travels as itself.
;;
;;   0  1000  "SOCONV"                the marker
;;   1  1000  the version that wrote it
;;   2  1000  the layer it came off
;;   3  1000  its linetype, "" unless the run forced BYLAYER
;;   4  1070  that layer's own colour, for a source layer since PURGEd
;;   5  1070  1 when the run forced BYLAYER, else 0
;;   6  1070  its colour,     256 (ByLayer) unless the run forced it
;;   7  1070  its lineweight, -1 (ByLayer)  unless the run forced it
;;
;; Only what the conversion actually overwrote is kept.  With the
;; forcing off -- the default, and what the sample does -- SOCONV
;; changes nothing but the layer, so nothing but the layer is written
;; down, and SORECONV puts nothing but the layer back.

;; NOT A KNOB: the number of items in the fixed part above, which
;; soconv:read indexes into.  Changing it does not change the record's
;; shape, it stops the reader agreeing with the writer.
(setq *soconv-record-len* 8)

;; APP's items onto ENT, leaving every OTHER application's xdata alone.
;;
;; (entget ent) with no application list carries no xdata at all in
;; AutoCAD, so there this is the plain append the rest of the tree
;; writes.  The VM the tests run on hands back every group it holds,
;; xdata included, so the -3 already there is merged with rather than
;; doubled -- an entity cannot carry two of them, and assoc would only
;; ever find the first.
(defun soconv:xput (ent app items / ed x apps)
  (setq ed   (entget ent)
        x    (assoc -3 ed)
        apps (if x
               (vl-remove-if '(lambda (a) (= (car a) app)) (cdr x))
               '()))
  (setq apps (append apps (list (cons app items))))
  (entmod (if x
            (subst (cons -3 apps) x ed)
            (append ed (list (cons -3 apps)))))
)

;; APP's items off ENT.  The application name goes back with NO data
;; after it, which is how xdata is deleted -- an entmod that simply
;; omits the application leaves it exactly where it was.
(defun soconv:xdel (ent app / ed x apps)
  (setq ed (entget ent (list app))
        x  (assoc -3 ed))
  (if x
    (progn
      (setq apps (vl-remove-if '(lambda (a) (= (car a) app)) (cdr x)))
      (setq apps (append apps (list (list app))))
      (entmod (subst (cons -3 apps) x ed))))
)

;; The items ENT carries under our application, or nil.  An application
;; entry with nothing after it is one xdel has emptied, and reads as no
;; record at all -- which is what it is.
(defun soconv:xget (ent app / x a)
  (setq x (assoc -3 (entget ent (list app))))
  (if x (setq a (assoc app (cdr x))))
  (if (and a (cdr a)) (cdr a))
)

;; The colour to re-create a source layer with, read off the layer
;; while it is still there.  A layer that is switched OFF carries the
;; colour negated; the record keeps the colour and not the off-ness,
;; so a layer SORECONV has to re-create comes back visible.
(defun soconv:layer-color (name / tb c)
  (setq tb (tblsearch "LAYER" name)
        c  (if tb (cdr (assoc 62 tb))))
  (if (and c (/= c 0)) (abs c) *soconv-default-color*)
)

;; Written BEFORE the move, which is the only moment the object still
;; carries what the record is about.
(defun soconv:stamp (ent lay / obj forced)
  (regapp *soconv-xdata-app*)
  (setq obj    (vlax-ename->vla-object ent)
        forced *soconv-force-bylayer*)
  (soconv:xput ent *soconv-xdata-app*
    (list (cons 1000 *soconv-xdata-app*)
          (cons 1000 *soconv-version*)
          (cons 1000 lay)
          (cons 1000 (if forced (vla-get-Linetype obj) ""))
          (cons 1070 (soconv:layer-color lay))
          (cons 1070 (if forced 1 0))
          (cons 1070 (if forced (vla-get-Color obj) 256))
          (cons 1070 (if forced (vla-get-Lineweight obj) -1))))
)

;; (source-layer layer-colour forced? colour linetype lineweight) off
;; one object, or nil when it carries no record of ours.
(defun soconv:read (ent / items)
  (setq items (soconv:xget ent *soconv-xdata-app*))
  (if (and items
           (= *soconv-record-len* (length items))
           (= *soconv-xdata-app* (cdr (nth 0 items))))
    (list (cdr (nth 2 items))
          (cdr (nth 4 items))
          (= 1 (cdr (nth 5 items)))
          (cdr (nth 6 items))
          (cdr (nth 3 items))
          (cdr (nth 7 items))))
)

;; The colour to re-create source layer LAY with: the one the record
;; kept from the layer itself, off the first object that came off it.
;; An existing layer is never recoloured -- ensure-layer only ever uses
;; this when the layer has to be made -- so a drawing that still has
;; its export layers keeps their colours whatever the record says.
(defun soconv:color-for (lay recs / out r)
  (foreach r recs
    (if (and (null out) (= (strcase (nth 1 r)) (strcase lay)))
      (setq out (nth 2 r))))
  (if out out *soconv-default-color*)
)

;; Every (ename . record) in SS, in drawing order.
(defun soconv:recorded (ss / i ent rec out)
  (setq i 0 out '())
  (while (< i (sslength ss))
    (setq ent (ssname ss i))
    (if (and (entget ent) (setq rec (soconv:read ent)))
      (setq out (cons (cons ent rec) out)))
    (setq i (1+ i)))
  (reverse out)
)

;;; -------------------- the command -------------------------------------
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
    (if lzd:report (lzd:report "SOCONV" *soconv-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "SOCONV" *soconv-version*))

  (setq doc      (vla-get-ActiveDocument (vlax-get-acad-object))
        unlocked nil)

  (vla-StartUndoMark doc)
  (setq mark-open T)

  ;; What to convert: the highlight if there is one, else what is
  ;; picked at the prompt, else the whole drawing.  An import usually
  ;; IS the whole drawing, which is why Enter means that; highlight
  ;; first when two surveys share one drawing.
  (setq ss (ssget "_I"))
  (if lzd:watch (lzd:watch ss))
  (if (null ss)
    (progn
      (prompt "\nSelect the survey import to convert <Enter = whole drawing>: ")
      (setq ss (ssget))
      (if lzd:watch (lzd:watch ss))
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
        ;; the record first: after the move the object no longer
        ;; carries the layer, or the properties, it is about
        (if *soconv-record* (soconv:stamp (car job) (soconv:layer-of (car job))))
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
                     " - PURGE those layers once the result looks right."))
      (if *soconv-record*
        (princ "\n  SORECONV moves it all back; PURGE only when you are sure.")
        (princ (strcat "\n  *soconv-record* is off, so nothing was written"
                       " down - only U undoes this run."))))
    (progn
      (princ "\nSOCONV: nothing here is on the export's layers - nothing moved.")
      (princ (strcat "\n  It converts " (soconv:namelist (soconv:sources))
                     "."))))
  (princ))

(defun c:SORECONV (/ *error* doc unlocked mark-open ss recs r ent obj
                     lay srcs offs tally missing done n)

  ;; SOCONV's handler, for the same reasons (STANDARDS 5).
  (defun *error* (msg)
    (if unlocked (vl-catch-all-apply 'soconv:relock-layers (list unlocked)))
    (setq unlocked nil)
    (if mark-open (vl-catch-all-apply 'vla-EndUndoMark (list doc)))
    (setq mark-open nil)
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nSORECONV error: " msg)))
    (if lzd:report (lzd:report "SORECONV" *soconv-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "SORECONV" *soconv-version*))

  (setq doc      (vla-get-ActiveDocument (vlax-get-acad-object))
        unlocked nil
        missing  '())

  (vla-StartUndoMark doc)
  (setq mark-open T)

  ;; The scope SOCONV takes, taken the same way: the highlight if there
  ;; is one, else what is picked, else the whole drawing.  Only objects
  ;; carrying a record move either way, so Enter is as safe here as it
  ;; is there.
  (setq ss (ssget "_I"))
  (if lzd:watch (lzd:watch ss))
  (if (null ss)
    (progn
      (prompt "\nSelect the converted import to put back <Enter = whole drawing>: ")
      (setq ss (ssget))
      (if lzd:watch (lzd:watch ss))
      (if (null ss)
        (setq ss (ssget "_X")))))

  (setq recs (if ss (soconv:recorded ss)))

  (if recs
    (progn
      ;; the layers it goes back ONTO, and the layers it comes OFF.
      ;; A destination of the revert is an output layer, so it is
      ;; created when the conversion's own PURGE advice was taken --
      ;; with the colour the record kept from the layer itself.
      (setq srcs '() offs '())
      (foreach r recs
        (setq lay  (nth 1 r)
              srcs (soconv:add lay srcs)
              offs (soconv:add (soconv:layer-of (car r)) offs)))
      (foreach lay srcs
        (soconv:ensure-layer lay (soconv:color-for lay recs)))
      (setq unlocked (soconv:unlock-layers (append srcs offs) doc))

      (foreach r recs
        (setq ent  (car r)
              obj  (vlax-ename->vla-object ent)
              done T)
        (vla-put-Layer obj (nth 1 r))
        ;; only a run that FORCED the three properties wrote them down,
        ;; and only such a run has anything to put back
        (if (nth 3 r)
          (progn
            (vla-put-Color obj (nth 4 r))
            (vla-put-Lineweight obj (nth 6 r))
            (if (or (member (strcase (nth 5 r)) '("BYLAYER" "BYBLOCK"))
                    (tblsearch "LTYPE" (nth 5 r)))
              (vla-put-Linetype obj (nth 5 r))
              (setq missing (soconv:add (nth 5 r) missing)
                    done    nil))))
        ;; The record goes with the move it described -- but only when
        ;; the move is FINISHED.  An object whose linetype could not be
        ;; come back to keeps its record, so loading the linetype and
        ;; running SORECONV again really does finish it; deleting it
        ;; here would make that advice a lie.
        (if done (soconv:xdel ent *soconv-xdata-app*))
        (setq tally (soconv:bump (nth 1 r) tally)))

      (soconv:relock-layers unlocked)
      (setq unlocked nil)))

  (vla-EndUndoMark doc)
  (setq mark-open nil)

  (if recs
    (progn
      (setq n (length recs))
      (princ (strcat "\nSORECONV done: " (itoa n)
                     " object(s) put back -- " (soconv:tally-line tally) "."))
      (princ (strcat "\n  Off " (soconv:namelist offs)
                     " - this drawing is on the export's own layers again."))
      (if missing
        (princ (strcat "\n  Linetype " (soconv:namelist missing)
                       " is no longer loaded, so those objects kept BYLAYER"
                       " - LINETYPE-load it and run SORECONV again to finish"
                       " them."))))
    (progn
      (princ "\nSORECONV: nothing here carries a SOCONV record - nothing moved.")
      (princ "\n  It undoes a SOCONV run, and only from the record SOCONV")
      (princ "\n  leaves on every object it moves.  A drawing converted with")
      (princ "\n  *soconv-record* off, or by hand, carries none - U is the")
      (princ "\n  only way back from those.")))
  (princ))

(defun c:SOCONVVER ()
  (princ (strcat "\nSOCONV " *soconv-version*))
  (princ))

(princ (strcat "\nSOCONV " *soconv-version*
               " loaded.  Type SOCONV to run, SORECONV to undo one."))
(princ)
