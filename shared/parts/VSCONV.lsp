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
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;
;;; A VS trace arrives on the exporter's own numbered layers, and the
;;; office draws on POOL / POINTS / DIMENSION.  VSCONV is that rename,
;;; in one pass:
;;;
;;;   1. LAYERS - every object on a source layer moves to the layer
;;;      *vsconv-map* pairs it with, with color, linetype and lineweight
;;;      forced to BYLAYER so the moved geometry takes the destination
;;;      layer's own appearance rather than carrying the exporter's:
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
;;; work cannot be converted twice.  Locked layers among those touched
;;; are unlocked for the run and re-locked afterwards, on the error path
;;; too, and the whole run is one undo group.
;;; ======================================================================

(setq *vsconv-version* "v1.0")   ; announced on load; release_lisp.py
                                 ; reads this banner and stamps the
                                 ; dated twin in releases/ from it

(vl-load-com)

;; ---------------------------------------------------------------
;; Configuration
;; ---------------------------------------------------------------

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
(setq *vsconv-colors*
      '(("POOL"      . 4)      ; cyan, as the rest of the tree creates it
        ("POINTS"    . 6)      ; magenta - the pink the points show in
        ("DIMENSION" . 141)))  ; as CUSTBLOCK creates it

(setq *vsconv-default-color* 7)      ; a destination the table above
                                     ; does not name

(setq *vsconv-dim-style* "STANDARD"  ; the style the dimensions land in
      *vsconv-dim-xdata* "ACAD")     ; the application whose style
                                     ; overrides are removed with them;
                                     ; nil leaves the overrides on

;; ---------------------------------------------------------------
;; Helpers
;; ---------------------------------------------------------------

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

;; The source layers, the destination layers (once each, in the order
;; the table names them), and the color one is created with.
(defun vsconv:sources ()
  (mapcar 'car *vsconv-map*))

(defun vsconv:dests ( / out p)
  (foreach p *vsconv-map*
    (if (not (member (cdr p) out)) (setq out (cons (cdr p) out))))
  (reverse out))

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

;; ---------------------------------------------------------------
;; Main command
;; ---------------------------------------------------------------
(defun c:VSCONV (/ *error* doc unlocked mark-open srcs dests here
                   filter ss i ent ed lay dest obj dims empty p
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
        dests    (vsconv:dests)
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
      ;; The destinations have to exist, and be usable, before anything
      ;; is moved onto them.
      (foreach lay dests (cal:ensure-layer lay (vsconv:color lay)))

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

      ;; Unlock every layer the run is about to touch -- the sources it
      ;; takes from and the destinations it writes to.
      (setq unlocked (vsconv:unlock-layers (append here dests) doc))

      ;; ------------------------------------------------------------
      ;; 1. The layer move, everything BYLAYER
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
                (vsconv:force-bylayer obj)
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
      (setq empty nil)
      (if (> n-moved 0)
        (foreach lay here
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
