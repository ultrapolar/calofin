;;; ======================================================================
;;; VSCONV.lsp  --  a VS survey export converted onto the calofin layers
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (Visual LISP - ActiveX is used throughout).
;;;
;;; Commands:  VSCONV     convert the import - highlight it first, or
;;;                       press Enter and take every VS layer in the
;;;                       drawing
;;;            VSRECONV   put a converted import back on the VS layers,
;;;                       style overrides and all
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
;;;
;;; VSRECONV PUTS ALL OF IT BACK.  U undoes a run still in the session;
;;; VSRECONV undoes one that was saved and reopened -- which is when a
;;; sheet turns out to have been converted by mistake, or has to go
;;; back to whoever exported it.  Every object VSCONV moves carries a
;;; RECORD in its own xdata: the layer it came off and that layer's
;;; colour, the colour, linetype and lineweight the BYLAYER forcing
;;; overwrote, and -- for a dimension -- the style name it had AND the
;;; whole ACAD/DSTYLE override block, kept verbatim as the xdata items
;;; it already was, so the text height and arrow size the export wrote
;;; come back exactly as they went in.  Both halves of the dimension
;;; step are undone, or the revert would leave the dimensions drawing
;;; in a style they never had.
;;;
;;; ONE THING THE REVERT SPELLS OUT rather than restores: an object
;;; that arrived carrying NO colour, linetype or lineweight of its own
;;; comes back carrying an explicit ByLayer -- 256, "ByLayer", -1 --
;;; where it had the absent group that means the same thing.  It draws
;;; and plots identically, and a DXF diff of the before and after says
;;; so; nothing else about the round trip is approximate.
;;; ======================================================================

(setq *vsconv-version* "v1.3")   ; announced on load; release_lisp.py
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
;; The record is written either way and keeps its fixed shape, so with
;; the forcing off VSRECONV puts back the values the object still has.
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
;; overrides on and changes only the style name.  It is also the
;; application vsconv:stamp reads the overrides from for the record.
(setq *vsconv-dim-xdata* "ACAD")

;; The record VSRECONV reads back, and the application it lives under.
;; nil converts exactly as before and writes nothing down, so the run
;; can only be undone by U; the tests drive both ways.
(setq *vsconv-record*    t
      *vsconv-xdata-app* "VSCONV")

;;; -------------------- helpers -----------------------------------------

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
;; is DXF group 3 and can simply be written; the overrides come off
;; through vsconv:xdel, which deletes ONE application's xdata and
;; leaves every other application's where it is -- this file's own
;; record among them, since it is written before this runs.
(defun vsconv:restyle-dim (ent style app / ed)
  (setq ed (entget ent))
  (if (assoc 3 ed)
    (entmod (subst (cons 3 style) (assoc 3 ed) ed)))
  (if app (vsconv:xdel ent app))
  (entupd ent))


;;; -------------------- the record --------------------------------------
;; Nine xdata items in a fixed order, and then -- for a dimension --
;; the export's own override block copied straight in behind them.
;; xdata groups are typed, so there is no grammar here to get wrong: a
;; layer name carrying a "|" (an xref-dependent one does) travels as
;; itself, and the overrides travel as the xdata items they already
;; are rather than as a rendering of them.
;;
;;   0  1000  "VSCONV"                the marker
;;   1  1000  the version that wrote it
;;   2  1000  the layer it came off
;;   3  1000  its linetype, before the BYLAYER forcing
;;   4  1000  its dimension style, "" for anything but a dimension
;;   5  1070  that layer's own colour, for a source layer since PURGEd
;;   6  1070  its colour,     before the forcing
;;   7  1070  its lineweight, before the forcing
;;   8  1070  1 when an override block follows, else 0
;;   9+       that block, item for item, braces and all
;;
;; The block is already brace-balanced where it stands, so it needs no
;; wrapper of its own -- and must not be given one, because AutoCAD
;; refuses xdata whose braces do not balance.

;; NOT A KNOB: the number of items in the fixed part above, which
;; vsconv:read indexes into and after which the override block starts.
;; Changing it does not change the record's shape, it stops the reader
;; agreeing with the writer.
(setq *vsconv-record-len* 9)

;; APP's items onto ENT, leaving every OTHER application's xdata alone.
;;
;; (entget ent) with no application list carries no xdata at all in
;; AutoCAD, so there this is the plain append the rest of the tree
;; writes.  The VM the tests run on hands back every group it holds,
;; xdata included, so the -3 already there is merged with rather than
;; doubled -- an entity cannot carry two of them, and assoc would only
;; ever find the first.
(defun vsconv:xput (ent app items / ed x apps)
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
;; after it, which is how xdata is deleted: an entmod list that simply
;; omits the application leaves its xdata exactly where it was.
(defun vsconv:xdel (ent app / ed x apps)
  (setq ed (entget ent (list app))
        x  (assoc -3 ed))
  (if x
    (progn
      (setq apps (vl-remove-if '(lambda (a) (= (car a) app)) (cdr x)))
      (setq apps (append apps (list (list app))))
      (entmod (subst (cons -3 apps) x ed))))
)

;; The items ENT carries under APP, or nil.  An application entry with
;; nothing after it is one xdel has emptied, and reads as no items --
;; which is what it is.
(defun vsconv:xget (ent app / x a)
  (setq x (assoc -3 (entget ent (list app))))
  (if x (setq a (assoc app (cdr x))))
  (if (and a (cdr a)) (cdr a))
)

;; LST with its first N items dropped.
(defun vsconv:tail (lst n)
  (while (and lst (> n 0)) (setq lst (cdr lst) n (1- n)))
  lst
)

;; The colour to re-create a source layer with, read off the layer
;; while it is still there.  A layer that is switched OFF carries the
;; colour negated; the record keeps the colour and not the off-ness, so
;; a layer VSRECONV has to re-create comes back visible.
(defun vsconv:layer-color (name / tb c)
  (setq tb (tblsearch "LAYER" name)
        c  (if tb (cdr (assoc 62 tb))))
  (if (and c (/= c 0)) (abs c) *vsconv-default-color*)
)

;; Written BEFORE the move and before the restyle, which is the only
;; moment the object still carries everything the record is about.
(defun vsconv:stamp (ent lay / obj typ sty ovr)
  (regapp *vsconv-xdata-app*)
  (setq obj (vlax-ename->vla-object ent)
        typ (cdr (assoc 0 (entget ent))))
  ;; only a DIMENSION has a style to lose or overrides to lose it to,
  ;; and group 3 means something else entirely on an MTEXT
  (if (= "DIMENSION" typ)
    (setq sty (cdr (assoc 3 (entget ent)))
          ovr (if *vsconv-dim-xdata* (vsconv:xget ent *vsconv-dim-xdata*))))
  (vsconv:xput ent *vsconv-xdata-app*
    (append (list (cons 1000 *vsconv-xdata-app*)
                  (cons 1000 *vsconv-version*)
                  (cons 1000 lay)
                  (cons 1000 (vla-get-Linetype obj))
                  (cons 1000 (if sty sty ""))
                  (cons 1070 (vsconv:layer-color lay))
                  (cons 1070 (vla-get-Color obj))
                  (cons 1070 (vla-get-Lineweight obj))
                  (cons 1070 (if ovr 1 0)))
            (if ovr ovr '())))
)

;; (source-layer layer-colour colour linetype lineweight style
;;  overrides) off one object, or nil when it carries no record of ours.
(defun vsconv:read (ent / items)
  (setq items (vsconv:xget ent *vsconv-xdata-app*))
  (if (and items
           (<= *vsconv-record-len* (length items))
           (= *vsconv-xdata-app* (cdr (nth 0 items))))
    (list (cdr (nth 2 items))
          (cdr (nth 5 items))
          (cdr (nth 6 items))
          (cdr (nth 3 items))
          (cdr (nth 7 items))
          (cdr (nth 4 items))
          (if (= 1 (cdr (nth 8 items)))
            (vsconv:tail items *vsconv-record-len*))))
)

;; NAME added to LST unless a spelling of it is in there already; the
;; order is first-seen, which is the order the report reads in.
(defun vsconv:add (name lst)
  (if (member (strcase name) (mapcar 'strcase lst))
    lst
    (append lst (list name)))
)

;; The colour to re-create source layer LAY with: the one the record
;; kept from the layer itself, off the first object that came off it.
;; An existing layer is never recoloured -- ensure-layer only ever uses
;; this when the layer has to be made -- so a drawing that still has
;; its export layers keeps their colours whatever the record says.
(defun vsconv:color-for (lay recs / out r)
  (foreach r recs
    (if (and (null out) (= (strcase (nth 1 r)) (strcase lay)))
      (setq out (nth 2 r))))
  (if out out *vsconv-default-color*)
)

;; Every (ename . record) in SS, in drawing order.
(defun vsconv:recorded (ss / i ent rec out)
  (setq i 0 out '())
  (while (< i (sslength ss))
    (setq ent (ssname ss i))
    (if (and (entget ent) (setq rec (vsconv:read ent)))
      (setq out (cons (cons ent rec) out)))
    (setq i (1+ i)))
  (reverse out)
)

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
    (if lzd:report (lzd:report "VSCONV" *vsconv-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "VSCONV" *vsconv-version*))

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
          (if lzd:watch (lzd:watch ss))
          (if (null ss) (setq ss (ssget "_X" filter)))))

      ;; The destinations have to exist, and be usable, before anything
      ;; is moved onto them -- but only the ones THIS selection reaches:
      ;; a survey with no dimensions in it does not want an empty
      ;; DIMENSION layer created for it, and a highlight of the anchors
      ;; alone wants POINTS and nothing else.
      (setq plan    (vsconv:plan ss)
            froms   (car plan)
            reached (cadr plan))
      (foreach lay reached (cal:ensure-layer lay (vsconv:color lay)))

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
                ;; the record first: after the move and the restyle the
                ;; object no longer carries the layer, the properties or
                ;; the overrides it is about
                (if *vsconv-record* (vsconv:stamp ent lay))
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
                       " them so one U backs the whole run out")))
      (if (> n-moved 0)
        (if *vsconv-record*
          (princ "\n  VSRECONV puts it all back, overrides and all.")
          (princ (strcat "\n  *vsconv-record* is off, so nothing was written"
                         " down - only U undoes this run."))))))

  ;; A mark is still open on the "nothing to convert" path above.
  (if mark-open
    (progn (vla-EndUndoMark doc) (setq mark-open nil)))
  (princ))

(defun c:VSRECONV (/ *error* doc unlocked mark-open ss recs r ent obj ed
                     lay srcs offs tally missing done n n-dim)

  ;; VSCONV's handler, for the same reasons (STANDARDS 5).
  (defun *error* (msg)
    (if unlocked (vl-catch-all-apply 'vsconv:relock-layers (list unlocked)))
    (setq unlocked nil)
    (if mark-open (vl-catch-all-apply 'vla-EndUndoMark (list doc)))
    (setq mark-open nil)
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nVSRECONV error: " msg)))
    (if lzd:report (lzd:report "VSRECONV" *vsconv-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "VSRECONV" *vsconv-version*))

  (setq doc      (vla-get-ActiveDocument (vlax-get-acad-object))
        unlocked nil
        missing  '()
        n-dim    0)

  (vla-StartUndoMark doc)
  (setq mark-open T)

  ;; No layer filter here, where VSCONV has one.  A converted object is
  ;; on POOL / POINTS / DIMENSION, which is where this office's own
  ;; drawing lives too -- so the record is what says which objects came
  ;; from an export, and nothing else is touched whatever is selected.
  (setq ss (ssget "_I"))
  (if lzd:watch (lzd:watch ss))
  (if (null ss)
    (progn
      (prompt "\nSelect the converted import to put back <Enter = whole drawing>: ")
      (setq ss (ssget))
      (if lzd:watch (lzd:watch ss))
      (if (null ss)
        (setq ss (ssget "_X")))))

  (setq recs (if ss (vsconv:recorded ss)))

  (if recs
    (progn
      ;; the layers it goes back ONTO, and the layers it comes OFF.  A
      ;; destination of the revert is an output layer, so it is created
      ;; when the conversion's own PURGE advice was taken -- with the
      ;; colour the record kept from the layer itself.
      (setq srcs '() offs '())
      (foreach r recs
        (setq lay  (nth 1 r)
              srcs (vsconv:add lay srcs)
              offs (vsconv:add (cdr (assoc 8 (entget (car r)))) offs)))
      (foreach lay srcs
        (cal:ensure-layer lay (vsconv:color-for lay recs)))
      (setq unlocked (vsconv:unlock-layers (append srcs offs) doc))

      (foreach r recs
        (setq ent  (car r)
              obj  (vlax-ename->vla-object ent)
              done T)
        (vla-put-Layer obj (nth 1 r))
        (vla-put-Color obj (nth 3 r))
        (vla-put-Lineweight obj (nth 5 r))
        (if (or (member (strcase (nth 4 r)) '("BYLAYER" "BYBLOCK"))
                (tblsearch "LTYPE" (nth 4 r)))
          (vla-put-Linetype obj (nth 4 r))
          (setq missing (vsconv:add (nth 4 r) missing)
                done    nil))
        ;; the dimension step, both halves: the style name back in
        ;; group 3, and the override block back under its own
        ;; application exactly as it was lifted
        (if (and (nth 6 r) (/= "" (nth 6 r)))
          (progn
            (setq ed (entget ent))
            (if (assoc 3 ed)
              (entmod (subst (cons 3 (nth 6 r)) (assoc 3 ed) ed)))
            (if (and (nth 7 r) *vsconv-dim-xdata*)
              (vsconv:xput ent *vsconv-dim-xdata* (nth 7 r)))
            (entupd ent)
            (setq n-dim (1+ n-dim))))
        ;; The record goes with the move it described -- but only when
        ;; the move is FINISHED.  An object whose linetype could not be
        ;; come back to keeps its record, so loading the linetype and
        ;; running VSRECONV again really does finish it; deleting it
        ;; here would make that advice a lie.
        (if done (vsconv:xdel ent *vsconv-xdata-app*))
        (setq tally (vsconv:bump (strcase (nth 1 r)) tally)))

      (vsconv:relock-layers unlocked)
      (setq unlocked nil)))

  (vla-EndUndoMark doc)
  (setq mark-open nil)

  (if recs
    (progn
      (setq n (length recs))
      (princ (strcat "\nVSRECONV done: " (itoa n)
                     " object(s) put back on the export's own layers."))
      ;; in the table's own order, as VSCONV reports it
      (foreach r *vsconv-map*
        (if (setq lay (assoc (strcase (car r)) tally))
          (princ (strcat "\n  " (cdr r) ": " (itoa (cdr lay))
                         " -> " (car r)))))
      (if (> n-dim 0)
        (princ (strcat "\n  " (itoa n-dim) " dimension(s) back on their own"
                       " style"
                       (if *vsconv-dim-xdata*
                         (strcat ", " *vsconv-dim-xdata*
                                 " style overrides restored")
                         ""))))
      (if missing
        (princ (strcat "\n  Linetype " (vsconv:namelist missing)
                       " is no longer loaded, so those objects kept BYLAYER"
                       " - LINETYPE-load it and run VSRECONV again to finish"
                       " them."))))
    (progn
      (princ "\nVSRECONV: nothing here carries a VSCONV record - nothing moved.")
      (princ "\n  It undoes a VSCONV run, and only from the record VSCONV")
      (princ "\n  leaves on every object it moves.  A drawing converted with")
      (princ "\n  *vsconv-record* off, or by hand, carries none - U is the")
      (princ "\n  only way back from those.")))
  (princ))

(defun c:VSCONVVER ()
  (princ (strcat "\nVSCONV " *vsconv-version*))
  (princ))

;; Quiet inside the whole build: LAZPASS.lsp and
;; CALOFIN-LOADER.lsp set the flag while they load their members,
;; because one file's greeting is a greeting and sixty-three of
;; them is a wall the drafter scrolls past in every drawing they
;; open.  APPLOADed alone the flag is nil and this prints, which
;; is the one time somebody wants to be told.  CALVER reports the
;; whole roster whenever it is asked.
(if (not *calofin-quiet*)
  (princ (strcat "\nVSCONV " *vsconv-version*
                 " loaded.  Type VSCONV to run, VSRECONV to undo one.")))
(princ)
