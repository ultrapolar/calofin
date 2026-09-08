;;; ======================================================================
;;; VSCONV.lsp  --  a VS survey export converted onto the calofin layers
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (Visual LISP - ActiveX is used throughout).
;;;
;;; Commands:  VSCONV     convert the import - highlight it first, or
;;;                       press Enter and take every VS layer in the
;;;                       drawing
;;;            VSCONVVER  print the loaded version
;;;
;;; A VS trace arrives on the exporter's own numbered layers, and the
;;; office draws on POOL / POINTS / DIMENSION.  VSCONV is that rename,
;;; in one pass:
;;;
;;;   1. LAYERS - every object on a source layer moves to the layer
;;;      *vsconv-map* pairs it with, with color, linetype and lineweight
;;;      forced to BYLAYER (*vsconv-force-bylayer*) so the moved geometry
;;;      takes the destination layer's own appearance rather than
;;;      carrying the exporter's:
;;;
;;;        "1 Perimeter"  -> POOL       the outline
;;;        "2 Coping"     -> POOL       the coping band
;;;        "3 Features"   -> POOL       steps, benches, the skimmer
;;;        "3.1 Anchors"  -> POINTS     the survey points (POINTS is
;;;                                     magenta, so they show pink)
;;;        "4 Dimensions" -> DIMENSION  the exporter's dimensions
;;;
;;;      Three source layers landing on POOL is the point of the table
;;;      rather than a flaw in it: perimeter, coping and features are
;;;      one drawing to this office and three to the exporter.
;;;
;;;   2. DIMENSIONS - every dimension that came over is put on the shop
;;;      dimension style (STANDARD) AND has its style OVERRIDES removed.
;;;      Both halves matter.  The exporter writes text height, arrow
;;;      size and decimal places into each dimension as an ACAD/DSTYLE
;;;      xdata block, and an override outranks the style it sits on - so
;;;      a dimension merely renamed to STANDARD would still draw itself
;;;      in the exporter's 2.5-unit text.  Strip the block and the style
;;;      is finally the thing that decides.
;;;
;;; WHAT IT DOES NOT DO.  There is no text step: a VS export carries no
;;; point labels, so there is nothing to restyle.  A drone trace that
;;; DOES arrive labelled is DRONE's or TYDRN's job (lisp/drone/,
;;; lisp/tydrn/) - the two are siblings of this file, the same one-pass
;;; cleanup written for the survey that comes in with text on it.
;;; The emptied source layers are left in the drawing and named in the
;;; done line instead of being purged, so the whole run stays one U.
;;;
;;; Scope is what you highlight; Enter at the prompt takes every object
;;; on a source layer, drawing-wide.  Either way only the source layers
;;; in the table are touched, so a sheet that already carries converted
;;; work cannot be converted twice.  A locked SOURCE layer is unlocked
;;; for the run and re-locked afterwards, on the error path too.  The
;;; destination layers are output layers: only the ones the selection
;;; actually reaches are created, and one that exists but is frozen,
;;; locked or off is repaired for good, with a line saying so (STANDARDS
;;; 5).  The whole run is one undo group.
;;; ======================================================================

(setq *vsconv-version* "v1.1")   ; announced on load; release_lisp.py
                                 ; reads this banner and stamps the
                                 ; dated twin in releases/ from it

(vl-load-com)

;;; -------------------- tunables ----------------------------------------
;;; Everything an exporter or a shop might want changed, all in one
;;; block; nothing settable lives anywhere else in this file.  Each says
;;; what CHANGING it does.  setq any of them after loading -- in a
;;; startup file, say -- and the next run reads the new value.

;; source layer -> destination layer.  The conversion IS this table: an
;; exporter that names its layers differently is retuned here and
;; nothing else in the file changes.  These are exact layer names, not
;; patterns: they go into an ssget filter, which reads them as wcmatch
;; patterns, so a name carrying one of , * ? # @ ~ [ ] or ` would select
;; layers the rest of the file then does not know what to do with.
(setq *vsconv-map*
      '(("1 Perimeter"  . "POOL")
        ("2 Coping"     . "POOL")
        ("3 Features"   . "POOL")
        ("3.1 Anchors"  . "POINTS")
        ("4 Dimensions" . "DIMENSION")))

;; The color a destination layer is CREATED with, when the drawing does
;; not carry it yet.  A drawing that has the layer already keeps its own
;; color: this is a conversion, not a restyling of the office template.
;; Only the destinations a run actually reaches are created, so a
;; survey with no dimensions in it leaves no empty DIMENSION behind.
(setq *vsconv-colors*
      '(("POOL"      . 4)      ; cyan, as the rest of the tree creates it
        ("POINTS"    . 6)      ; magenta - the pink the points show in
        ("DIMENSION" . 141)))  ; as CUSTBLOCK creates it

;; The color for a destination the table above does not name - what a
;; retuned *vsconv-map* row pointing at a new layer gets.  7 is white.
(setq *vsconv-default-color* 7)

;; T, and every moved object has its color, linetype and lineweight set
;; to BYLAYER on the way past, so it takes the destination layer's own
;; appearance and nothing overrides it later.  That is the point of the
;; conversion - the VS export sets none of the three on purpose - and
;; the sample the tool was written from does it.  nil moves the layer
;; and leaves every other property as it arrived, which is what SOCONV
;; does by default because THAT export's sample does; the two tools
;; carry the same switch with opposite defaults, each for its export.
(setq *vsconv-force-bylayer* T)

;; The dimension style every converted dimension is put on.  If the
;; drawing has no style by this name the dimensions still move layer,
;; but keep the export's style AND its overrides - the style is what
;; would have replaced them - and the run says so once.
(setq *vsconv-dim-style* "STANDARD")

;; The xdata application whose style overrides come off each dimension
;; with the restyle.  AutoCAD keeps a dimension's per-object overrides
;; (text height, arrow size, decimals) as DSTYLE xdata under "ACAD",
;; and an override outranks the style it sits on, so leaving them would
;; keep the export's look under the shop's style name.  nil leaves the
;; overrides on and changes only the style name.
(setq *vsconv-dim-xdata* "ACAD")

;;; -------------------- helpers -----------------------------------------

;; Create the output layer, or - when it already exists - make sure it
;; is on, thawed and unlocked.  Without this a successful run onto a
;; frozen or switched-off layer looks like the command did nothing.
(defun vsconv:ensure-layer (name color / rec ed flags col fixed)
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
          (princ (strcat "\nVSCONV: layer " name
                         " was off, frozen or locked - restored so the"
                         " result is visible."))))))
  name)

;; Unlock every layer in NAMES that is currently locked and return the
;; list of layer objects that were unlocked (so they can be re-locked).
(defun vsconv:unlock-layers (names doc / layers obj unlocked name)
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

(defun vsconv:relock-layers (objs / obj)
  (foreach obj objs (vla-put-Lock obj :vlax-true)))

;; Reset color / linetype / lineweight of a vla-object to BYLAYER.
(defun vsconv:force-bylayer (obj)
  (vla-put-Color obj acByLayer)
  (vla-put-Linetype obj "ByLayer")
  (vla-put-Lineweight obj acLnWtByLayer))

;; The source layers the table names, and the color a destination is
;; created with.
(defun vsconv:sources ()
  (mapcar 'car *vsconv-map*))

(defun vsconv:color (name / p)
  (if (setq p (assoc (strcase name) (mapcar '(lambda (q)
                                               (cons (strcase (car q))
                                                     (cdr q)))
                                            *vsconv-colors*)))
    (cdr p)
    *vsconv-default-color*))

;; Where LAY converts to, nil for a layer the table does not name.
;; Layer names are case-insensitive in AutoCAD, so the lookup is too.
(defun vsconv:dest (lay / out p)
  (foreach p *vsconv-map*
    (if (and (null out) (= (strcase (car p)) (strcase lay)))
      (setq out (cdr p))))
  out)

;; Join names into the comma-separated form an ssget layer filter wants,
;; and into the plain English the report wants.
(defun vsconv:csv (names / out name)
  (foreach name names
    (setq out (if out (strcat out "," name) name)))
  out)

(defun vsconv:namelist (names / out name)
  (foreach name names
    (setq out (if out (strcat out ", " name) name)))
  out)

;; The source layers this drawing actually carries.
(defun vsconv:present (names / out name)
  (foreach name names
    (if (tblsearch "LAYER" name) (setq out (cons name out))))
  (reverse out))

;; Is there anything left on LAY?  ("_X" sweeps the database, so a
;; frozen or switched-off leftover still counts as one.)
(defun vsconv:empty-p (lay)
  (null (ssget "_X" (list (cons 8 lay)))))

;; What THIS selection touches, without touching anything: the source
;; layers it takes from and the destinations it writes to, each once,
;; in first-seen order.  Returns (sources destinations) - both nil for
;; an empty selection.  Sizing the run to the selection is what keeps a
;; highlight of the anchors alone from creating POOL and DIMENSION, or
;; from unlocking a perimeter layer it never reads.
(defun vsconv:plan (ss / i lay dest froms tos)
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq lay  (cdr (assoc 8 (entget (ssname ss i))))
              dest (vsconv:dest lay))
        (if dest
          (progn
            (if (not (member (strcase lay) (mapcar 'strcase froms)))
              (setq froms (append froms (list lay))))
            (if (not (member dest tos))
              (setq tos (append tos (list dest))))))
        (setq i (1+ i)))))
  (list froms tos))

;; KEY's count in an alist, one higher.
(defun vsconv:bump (key alist / p)
  (if (setq p (assoc key alist))
    (subst (cons key (1+ (cdr p))) p alist)
    (append alist (list (cons key 1)))))

;; One dimension onto the shop style, overrides and all.  The style name
;; is DXF group 3 and can simply be written; the overrides are xdata
;; under the "ACAD" application, and an application name handed to
;; entmod with NO data after it is how xdata is deleted.  The group has
;; to be there and empty for that: an entmod list that simply omits it
;; leaves the xdata exactly where it was.
(defun vsconv:restyle-dim (ent style app / ed x)
  (setq ed (if app (entget ent (list app)) (entget ent)))
  (if (assoc 3 ed)
    (setq ed (subst (cons 3 style) (assoc 3 ed) ed)))
  (if (and app (setq x (assoc -3 ed)))
    (setq ed (subst (list -3 (list app)) x ed)))
  (entmod ed)
  (entupd ent))

;;; -------------------- the command -------------------------------------
(defun c:VSCONV (/ *error* doc unlocked mark-open srcs here plan froms
                   reached filter ss i ent ed lay dest obj dims empty p
                   tally n-moved n-dim)

  ;; The handler is LOCAL to this command (STANDARDS 5), as DRONE's and
  ;; TYDRN's are: it sees doc / unlocked / mark-open through dynamic
  ;; scope, and closes only the mark this run opened -- the close can
  ;; itself throw when the failure came before StartUndoMark, and a
  ;; throw inside *error* is the one error nothing can catch.
  (defun *error* (msg)
    ;; locked layers come back FIRST so nothing below can skip them
    ;; through the catch: a Lock put that throws must not skip the mark
    ;; close below -- a throw inside *error* is uncatchable
    (if unlocked (vl-catch-all-apply 'vsconv:relock-layers (list unlocked)))
    (setq unlocked nil)
    (if mark-open (vl-catch-all-apply 'vla-EndUndoMark (list doc)))
    (setq mark-open nil)
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nVSCONV error: " msg)))
    (princ))

  (setq doc      (vla-get-ActiveDocument (vlax-get-acad-object))
        unlocked nil
        srcs     (vsconv:sources)
        here     (vsconv:present srcs)
        tally    nil
        dims     nil
        n-moved  0
        n-dim    0)

  (vla-StartUndoMark doc)
  (setq mark-open T)

  (if (null here)
    ;; Nothing of the exporter's is in this drawing.  Say which layers
    ;; were looked for rather than "0 objects converted": the usual
    ;; cause is a drawing that was converted already, and the second is
    ;; an exporter whose layer names have changed under the table.
    (progn
      (princ (strcat "\nVSCONV: this drawing carries none of the VS"
                     " layers (" (vsconv:namelist srcs) ")."))
      (princ "\n  Nothing to convert - either it has been through VSCONV")
      (princ "\n  already, or the export names its layers differently now")
      (princ "\n  and *vsconv-map* is what needs editing."))
    (progn
      ;; ------------------------------------------------------------
      ;; What to convert: the highlight, else a prompt, Enter = every
      ;; object on a source layer anywhere in the drawing.
      ;; ------------------------------------------------------------
      (setq filter (list (cons 8 (vsconv:csv srcs)))
            ss     (ssget "_I" filter))
      (if (null ss)
        (progn
          (prompt (strcat "\nSelect the VS import <Enter = every VS layer"
                          " in the drawing>: "))
          (setq ss (ssget filter))
          (if (null ss) (setq ss (ssget "_X" filter)))))

      ;; The destinations have to exist, and be usable, before anything
      ;; is moved onto them -- but only the ones THIS selection reaches:
      ;; a survey with no dimensions in it does not want an empty
      ;; DIMENSION layer created for it, and a highlight of the anchors
      ;; alone wants POINTS and nothing else.
      (setq plan    (vsconv:plan ss)
            froms   (car plan)
            reached (cadr plan))
      (foreach lay reached (vsconv:ensure-layer lay (vsconv:color lay)))

      ;; Unlock every layer the run is about to touch -- the sources it
      ;; takes from and the destinations it writes to, both sized to
      ;; the selection.
      (setq unlocked (vsconv:unlock-layers (append froms reached) doc))

      ;; ------------------------------------------------------------
      ;; 1. The layer move, everything BYLAYER when asked (the default)
      ;; ------------------------------------------------------------
      (if ss
        (progn
          (setq i 0)
          (while (< i (sslength ss))
            (setq ent  (ssname ss i)
                  ed   (entget ent)
                  lay  (cdr (assoc 8 ed))
                  dest (vsconv:dest lay))
            (if dest
              (progn
                (setq obj (vlax-ename->vla-object ent))
                (vla-put-Layer obj dest)
                (if *vsconv-force-bylayer* (vsconv:force-bylayer obj))
                (setq tally   (vsconv:bump (strcase lay) tally)
                      n-moved (1+ n-moved))
                ;; the dimensions are collected rather than restyled
                ;; here: the style may be missing, which is one message
                ;; about all of them and not one per dimension
                (if (= "DIMENSION" (cdr (assoc 0 ed)))
                  (setq dims (cons ent dims)))))
            (setq i (1+ i)))))

      ;; ------------------------------------------------------------
      ;; 2. The dimensions onto the shop style, overrides removed
      ;; ------------------------------------------------------------
      (if dims
        (if (tblsearch "DIMSTYLE" *vsconv-dim-style*)
          (foreach ent (reverse dims)
            (vsconv:restyle-dim ent *vsconv-dim-style* *vsconv-dim-xdata*)
            (setq n-dim (1+ n-dim)))
          (princ (strcat "\nVSCONV: this drawing has no \""
                         *vsconv-dim-style* "\" dimension style, so the "
                         (itoa (length dims)) " dimension(s) moved layer"
                         " but kept the export's style and overrides."))))

      ;; Re-lock whatever we unlocked and close the undo group.
      (vsconv:relock-layers unlocked)
      (setq unlocked nil)
      (vla-EndUndoMark doc)
      (setq mark-open nil)

      ;; ------------------------------------------------------------
      ;; The report, in the table's own order
      ;; ------------------------------------------------------------
      (princ (strcat "\nVSCONV done: " (itoa n-moved)
                     " object(s) converted."))
      (foreach p *vsconv-map*
        (if (setq lay (assoc (strcase (car p)) tally))
          (princ (strcat "\n  " (car p) ": " (itoa (cdr lay))
                         " -> " (cdr p)))))
      ;; The VS layers are here but nothing is on them - the selection
      ;; is everything on them, so an empty selection means empty
      ;; layers.  That is not the same as the drawing not being an
      ;; export, so it is not the same message; and nothing was emptied
      ;; by this run, so the line below is not printed either.
      (if (= 0 n-moved)
        (princ (strcat "\n  the VS layers (" (vsconv:namelist here)
                       ") carry nothing - nothing to convert.")))
      (if (> n-dim 0)
        (princ (strcat "\n  " (itoa n-dim) " dimension(s) -> "
                       *vsconv-dim-style*
                       (if *vsconv-dim-xdata*
                         (strcat ", " *vsconv-dim-xdata*
                                 " style overrides removed")
                         ""))))
      ;; Only the layers this run actually took objects OFF can have
      ;; been emptied by it, so froms is what is walked rather than
      ;; every source layer present: an export with nothing dimensioned
      ;; carries an empty "4 Dimensions" in before the run, and naming
      ;; it here would send the drafter to purge a layer this run never
      ;; touched.
      (setq empty nil)
      (if (> n-moved 0)
        (foreach lay froms
          (if (vsconv:empty-p lay) (setq empty (cons lay empty)))))
      (if empty
        (princ (strcat "\n  now empty: " (vsconv:namelist (reverse empty))
                       " - PURGE them when you are ready; VSCONV leaves"
                       " them so one U backs the whole run out")))))

  ;; A mark is still open on the "nothing to convert" path above.
  (if mark-open
    (progn (vla-EndUndoMark doc) (setq mark-open nil)))
  (princ))

(defun c:VSCONVVER ()
  (princ (strcat "\nVSCONV " *vsconv-version*))
  (princ))

(princ (strcat "\nVSCONV " *vsconv-version*
               " loaded.  Type VSCONV to run."))
(princ)
