;;; ======================================================================
;;; G2MCONV.lsp  --  a G2M architectural export onto the calofin layers
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (Visual LISP - ActiveX is used throughout).
;;;
;;; Commands:  G2MCONV     convert the export - highlight it first, or
;;;                        press Enter and take every G2M layer in the
;;;                        drawing
;;;            G2MRECONV   put a converted export back on the G2M
;;;                        layers, styles and overrides and all
;;;            G2MCONVVER  print the loaded version
;;;
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;
;;; A G2M plan arrives from an architect rather than a surveyor: AIA
;;; layer names with a Spanish half after them ("A-STAIRS - GRADAS"),
;;; the architect's own text and dimension styles, and an annotative
;;; flag on the dimensions.  The office draws on POOL / TEXT /
;;; DIMENSION.  G2MCONV is that move, in one pass, off the before/after
;;; sample the shop supplied (G2MCONV.dxf -- one plan converted by hand,
;;; kept beside the original in the one drawing):
;;;
;;;   from the export                what is on it   onto        linetype
;;;   ----------------------------   -------------   ---------   --------
;;;   1 A POOL WALL - PARED PISCINA  everything      POOL        ByLayer
;;;   A-STAIRS - GRADAS              everything      POOL        DASHED2
;;;   A-ANNO-TEXT - TEXTO            everything      TEXT        ByLayer
;;;   A-ANNO-DIMS - DIMENSIONES      text, leaders   TEXT        ByLayer
;;;   A-ANNO-DIMS - DIMENSIONES      everything else DIMENSION   ByLayer
;;;
;;; TWO SOURCE LAYERS LAND ON POOL.  The wall and the stairs are one
;;; drawing to this office and two to the architect -- but they do NOT
;;; arrive looking alike, and the sample keeps that: the wall is drawn
;;; solid and the stairs in the architect's HIDDEN2, which is the whole
;;; point of a stair under water.  So the stairs row carries the shop's
;;; own dashed pattern rather than ByLayer, and the two land on one
;;; layer still telling each other apart.
;;;
;;; THE EXPORT'S ONE ANNOTATION LAYER SPLITS IN TWO, the way SOCONV's
;;; does: the notes are caught by the text row, and the catch-all under
;;; it takes the dimensions and whatever else the architect left there.
;;;
;;; Then the three things a layer move alone would leave looking wrong,
;;; each of them an override that outranks the layer or style it sits
;;; on:
;;;
;;;   1. APPEARANCE - colour, linetype and lineweight go BYLAYER
;;;      (*g2mconv-force-bylayer* for the first and last; the linetype
;;;      is the map's fourth column, because of the stairs) and its
;;;      fifth carries the linetype scale, the shop drawing's own
;;;      CELTSCALE.  The export writes an explicit "Continuous" onto
;;;      geometry that then cannot follow its layer; the sample takes
;;;      it off.
;;;
;;;   2. TEXT - every note is put on the shop text style (Attributes)
;;;      at the shop text height (9.5).  The architect's text arrives
;;;      in Century Gothic at 4.384, which is a paper height scaled by
;;;      a viewport, and it reads as half-size beside the shop's own.
;;;
;;;   3. DIMENSIONS - every dimension is put on the shop dimension
;;;      style (STANDARD) AND has its style OVERRIDES removed, the way
;;;      VSCONV does, AND stops being annotative.  All three matter and
;;;      for one reason: an override outranks the style it sits on, so
;;;      a dimension merely renamed to STANDARD would still draw itself
;;;      in the architect's text through its ACAD/DSTYLE block, and an
;;;      annotative one would still scale itself by the viewport.
;;;
;;; The three numbers in 1 and 2 are not invented: they are $CELTSCALE,
;;; $TEXTSTYLE and $TEXTSIZE as the shop drawing carries them, which is
;;; what the drafter's hand conversion put on every object it touched.
;;;
;;; WHAT IT DOES NOT DO.  Nothing is erased and nothing is drawn.  The
;;; leaders keep their own multileader style and the text inside them
;;; keeps its height -- the sample restyles the standalone notes and
;;; leaves the leaders alone, and so does this.  The emptied source
;;; layers are left in the drawing and named in the done line instead
;;; of being purged, so the whole run stays one U.
;;;
;;; TWO THINGS IN THE SAMPLE ARE EDITS RATHER THAN RULES, and are not
;;; in here.  Its after side leaves three objects behind on the export
;;; layers -- one arc, one leader and one GRASS note -- where the same
;;; objects either side of them converted; the drafter's window missed
;;; them, and the give-away is that the other five notes on that layer
;;; went across.  And three of the converted notes have a defined width
;;; of exactly 130 where the rest carry the width AutoCAD recomputed
;;; for them; that is a drag of the text box, not a number this tool
;;; could know.  MTEXT widths are left to AutoCAD here, which is what
;;; produced every other width in the sample.
;;;
;;; ONE JUDGEMENT CALL THE SAMPLE DOES NOT SETTLE: which way a leader
;;; on the annotation layer goes.  The drafter sent six of the twelve
;;; to TEXT and five to DIMENSION and left one behind, and the twelve
;;; are otherwise identical -- same multileader style, same "4"" in
;;; most of them -- so there is no rule in there to find, only a window
;;; that was dragged twice.  They go to TEXT: a leader is a note with a
;;; line attached, it is where the majority went, and it is what SOCONV
;;; already does with the notes on ITS export's dimension layer.  The
;;; fourth row of *g2mconv-map* is the one line that changes its mind.
;;;
;;; Scope is what you highlight; Enter at the prompt takes every object
;;; on a source layer, drawing-wide.  Either way only the source layers
;;; in the table are touched, so a sheet that already carries converted
;;; work cannot be converted twice.  A locked SOURCE layer is unlocked
;;; for the run and re-locked afterwards, on the error path too.  The
;;; destination layers are output layers: only the ones the selection
;;; actually reaches are created, and one that exists but is frozen,
;;; locked or off is repaired for good, with a line saying so
;;; (STANDARDS 5).  The whole run is one undo group.
;;;
;;; G2MRECONV PUTS ALL OF IT BACK.  U undoes a run still in the
;;; session; G2MRECONV undoes one that was saved and reopened -- which
;;; is when a sheet turns out to have been converted by mistake, or has
;;; to go back to the architect it came from.  Every object G2MCONV
;;; moves carries a RECORD in its own xdata: the layer it came off and
;;; that layer's colour, the colour, linetype, lineweight and linetype
;;; scale the appearance step overwrote, the text style and height the
;;; text step overwrote, the annotative flag, and -- for a dimension --
;;; the style name it had AND the whole ACAD/DSTYLE override block,
;;; kept verbatim as the xdata items it already was.  Every step is
;;; undone, or the revert would leave the drawing in a state neither
;;; the architect nor the shop ever drew.  A linetype or a style the
;;; record names that the drawing no longer has stops that object being
;;; finished: it KEEPS its record and is named in the report, so
;;; loading the pattern or the style back and running G2MRECONV again
;;; finishes the job rather than finding nothing left to do.
;;;
;;; ONE THING THE REVERT SPELLS OUT rather than restores: an object
;;; that arrived carrying NO colour, linetype, lineweight or linetype
;;; scale of its own comes back carrying an explicit ByLayer -- 256,
;;; "ByLayer", -1, 1.0 -- where it had the absent group that means the
;;; same thing.  It draws and plots identically, and a DXF diff of the
;;; before and after says so; nothing else about the round trip is
;;; approximate.
;;; ======================================================================

(setq *g2mconv-version* "v1.0")   ; announced on load; release_lisp.py
                                  ; reads this banner and stamps the
                                  ; dated twin in releases/ from it

(vl-load-com)

;;; -------------------- tunables ----------------------------------------
;;; Everything an architect or a shop might want changed, all in one
;;; block; nothing settable lives anywhere else in this file.  Each says
;;; what CHANGING it does.  setq any of them after loading -- in a
;;; startup file, say -- and the next run reads the new value.

;; The conversion itself, one row per rule:
;;
;;     (source-layer  entity-types  destination  linetype  ltscale)
;;
;; The first two are wcmatch patterns -- "," is alternation, "*" is
;; anything -- and the rows are tried IN ORDER, the first match
;; winning.  That ordering is what lets the two annotation rows split
;; the export's one layer into two of ours.  An architect who names
;; layers differently is retuned HERE and nowhere else in the file: to
;; widen a row to a whole family, "A-STAIRS*" or "*GRADAS" both work.
;;
;; The fourth column is the linetype the moved object is given:
;; "ByLayer" so it follows the destination layer, or a pattern name to
;; force.  nil leaves whatever it arrived with.  The fifth is its
;; linetype scale: 0.4 is what this drawing gives anything drawn in it
;; -- its CELTSCALE -- so a converted object carries the same scale as
;; whatever the shop draws beside it later.  nil leaves the scale
;; alone, which is what the stairs row does, and that row is the only
;; one landing on a DASHED pattern rather than a continuous layer:
;; 0.4 would shrink it to two-fifths of the size the drawing's LTSCALE
;; was set for, closing it up until it reads solid.
;;
;; The scale is a COLUMN rather than a knob of its own on purpose.  A
;; global holding 0.4 beside a table that already spells it out four
;; times would be a setting nothing reads: the rows are quoted data, so
;; changing the global would move nothing -- and a knob that does
;; nothing when you set it is worse than no knob at all.
(setq *g2mconv-map*
  '(("1 A POOL WALL - PARED PISCINA" "*"                      "POOL"      "ByLayer" 0.4)
    ("A-STAIRS - GRADAS"             "*"                      "POOL"      "DASHED2" nil)
    ("A-ANNO-TEXT - TEXTO"           "*"                      "TEXT"      "ByLayer" 0.4)
    ("A-ANNO-DIMS - DIMENSIONES"     "TEXT,MTEXT,MULTILEADER" "TEXT"      "ByLayer" 0.4)
    ("A-ANNO-DIMS - DIMENSIONES"     "*"                      "DIMENSION" "ByLayer" 0.4)))

;; A linetype a map row names that the drawing has not got.  DASHED2 is
;; stock and this file can make it (the same entmake ABHD and FITABHD
;; use); anything else has to be loaded from an .lin file first, and a
;; run that meets one says so and leaves those objects' linetype alone
;; rather than failing halfway through.  nil stops it creating even
;; DASHED2.
(setq *g2mconv-make-dashed2* T)

;; The color a destination layer is CREATED with, when the drawing does
;; not carry it yet.  A drawing that has the layer already keeps its own
;; color: this is a conversion, not a restyling of the office template.
;; Only the destinations a run actually reaches are created, so an
;; export with no dimensions in it leaves no empty DIMENSION behind.
(setq *g2mconv-colors*
  '(("POOL"      . 4)      ; cyan, as POOL.LSP and POOLSIDE create it
    ("TEXT"      . 4)      ; as SOCONV creates it
    ("DIMENSION" . 141)))  ; as CUSTBLOCK creates it

;; The color for a destination the table above does not name - what a
;; retuned *g2mconv-map* row pointing at a new layer gets.  7 is white.
(setq *g2mconv-default-color* 7)

;; T, and every moved object has its color and lineweight set to
;; BYLAYER on the way past, so it takes the destination layer's own
;; appearance and nothing overrides it later.  (The linetype is the
;; map's own fourth column and is not covered by this switch, because
;; the stairs row needs a value rather than a yes/no.)  The sample
;; carries no explicit colour or lineweight to show either way, but it
;; does take the linetype to ByLayer, and this is the same intent
;; applied to the other two.  nil moves the layer and leaves both as
;; they arrived, which is what SOCONV does by default.
(setq *g2mconv-force-bylayer* T)

;; The text style and height every note the run moves is put on.  These
;; are the shop drawing's own TEXTSTYLE and TEXTSIZE.  If the drawing
;; has no style by this name the notes still move layer but keep the
;; architect's style AND height -- a height is measured for the style
;; it is set in, so half a restyle is worse than none -- and the run
;; says so once.  nil for the style leaves both alone on purpose.
(setq *g2mconv-text-style*  "Attributes"
      *g2mconv-text-height* 9.5)

;; The dimension style every converted dimension is put on.  If the
;; drawing has no style by this name the dimensions still move layer,
;; but keep the export's style AND its overrides - the style is what
;; would have replaced them - and the run says so once.
(setq *g2mconv-dim-style* "STANDARD")

;; The xdata application whose style overrides come off each dimension
;; with the restyle.  AutoCAD keeps a dimension's per-object overrides
;; (text height, arrow size, decimals) as DSTYLE xdata under "ACAD",
;; and an override outranks the style it sits on, so leaving them would
;; keep the architect's look under the shop's style name.  nil leaves
;; the overrides on and changes only the style name.  It is also the
;; application g2m:stamp reads the overrides from for the record.
;;
;; Only DIMENSIONS are read or stripped here.  An MTEXT keeps xdata
;; under "ACAD" too (ACAD_MTEXT_DEFINED_HEIGHT) and it is none of this
;; tool's business.
(setq *g2mconv-dim-xdata* "ACAD")

;; T, and an object that arrives ANNOTATIVE stops being so: its
;; annotative flag goes to 0 and it draws at the size it is set to
;; rather than at the viewport's annotation scale.  In the sample that
;; is the nine dimensions; the notes arrived with the flag already off.
;; nil leaves the flag alone, and an annotative dimension then keeps
;; scaling itself under the shop's style name.
(setq *g2mconv-deannotate* T)

;; The application the annotative flag lives under.  AutoCAD writes it
;; as AnnotativeData { <class> <flag> }, which is why the flag is the
;; SECOND 1070 in the block and the first is not ours to touch.
(setq *g2mconv-anno-xdata* "AcadAnnotative")

;; The record G2MRECONV reads back, and the application it lives under.
;; nil converts exactly as before and writes nothing down, so the run
;; can only be undone by U; the tests drive both ways.
(setq *g2mconv-record*    t
      *g2mconv-xdata-app* "G2MCONV")

;;; -------------------- helpers -----------------------------------------

;; Make sure the DASHED2 linetype exists - pure entmake, no command
;; calls, the same definition ABHD and FITABHD create it with.
(defun g2m:ensure-dashed2 ()
  (if (not (tblsearch "LTYPE" "DASHED2"))
    (entmake (list '(0 . "LTYPE") '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLinetypeTableRecord")
                   '(2 . "DASHED2") '(70 . 0)
                   '(3 . "Dashed (.5x) _ _ _ _ _")
                   '(72 . 65) '(73 . 2) '(40 . 9.0)
                   '(49 . 6.0) '(74 . 0)
                   '(49 . -3.0) '(74 . 0)))))

;; T when LT can be written onto an object right now: the two magic
;; words always can, a loaded pattern can, and DASHED2 is made on the
;; spot when the drawing has not got it.
(defun g2m:ltype-usable-p (lt)
  (cond ((null lt) nil)
        ((member (strcase lt) '("BYLAYER" "BYBLOCK")) T)
        ((tblsearch "LTYPE" lt) T)
        ((and *g2mconv-make-dashed2* (= (strcase lt) "DASHED2"))
         (g2m:ensure-dashed2)
         (if (tblsearch "LTYPE" lt) T))))

;; Unlock every layer in NAMES that is currently locked and return the
;; list of layer objects that were unlocked (so they can be re-locked).
(defun g2m:unlock-layers (names doc / layers obj unlocked name)
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

(defun g2m:relock-layers (objs / obj)
  (foreach obj objs (vla-put-Lock obj :vlax-true)))

;; NAME added to LST unless a spelling of it is in there already; the
;; order is first-seen, which is the order the report reads in.
(defun g2m:add (name lst)
  (if (member (strcase name) (mapcar 'strcase lst))
    lst
    (append lst (list name))))

;; The layer ENT is on right now.
(defun g2m:layer-of (ent)
  (cdr (assoc 8 (entget ent))))

;; The whole map ROW claiming an entity of type TYP on layer LAY, or
;; nil when none does.  Rows are tried in order and the first wins; the
;; caller reads the destination and the two appearance columns off the
;; row it gets back, so they can never come from different rules.
(defun g2m:rule (typ lay / rule out)
  (foreach rule *g2mconv-map*
    (if (and (null out)
             (wcmatch (strcase lay) (strcase (car rule)))
             (wcmatch (strcase typ) (strcase (cadr rule))))
      (setq out rule)))
  out)

;; DEST's count in TALLY, up by one -- appended when it is new, so the
;; tally stays in the order the destinations were first reached.
(defun g2m:bump (dest tally / p)
  (if (setq p (assoc dest tally))
    (subst (cons dest (1+ (cdr p))) p tally)
    (append tally (list (cons dest 1)))))

;; The source layers the map names, for the message that gets printed
;; when a drawing has none of them.
(defun g2m:sources ( / rule out)
  (foreach rule *g2mconv-map*
    (setq out (g2m:add (car rule) out)))
  out)

;; The colour to CREATE destination NAME with (see *g2mconv-colors*).
(defun g2m:color (name / rule out)
  (foreach rule *g2mconv-colors*
    (if (and (null out) (= (strcase (car rule)) (strcase name)))
      (setq out (cdr rule))))
  (if out out *g2mconv-default-color*))

;; "A-ANNO-DIMS - DIMENSIONES, A-STAIRS - GRADAS"
(defun g2m:namelist (names / out name)
  (foreach name names
    (setq out (strcat (if out (strcat out ", ") "") name)))
  out)

;; "32 -> POOL, 22 -> TEXT"
(defun g2m:tally-line (tally / out p)
  (foreach p tally
    (setq out (strcat (if out (strcat out ", ") "")
                      (itoa (cdr p)) " -> " (car p))))
  out)

;; T for the entity types the text step restyles.
(defun g2m:text-p (typ)
  (if (member (strcase typ) '("TEXT" "MTEXT")) T))

;; One DXF group written onto ENT, whether or not it is already there.
;; entmod cannot delete a group, so an absent one is APPENDED rather
;; than left out - which is the whole reason this is not a plain subst:
;; a linetype scale is a group most objects simply have not got.
(defun g2m:put-group (ent code val / ed p)
  (setq ed (entget ent)
        p  (assoc code ed))
  (entmod (if p
            (subst (cons code val) p ed)
            (append ed (list (cons code val)))))
)

;; One DXF group off ENT, or DFLT when it has not got it.
(defun g2m:group (ent code dflt / p)
  (if (setq p (assoc code (entget ent))) (cdr p) dflt))

;;; -------------------- xdata -------------------------------------------

;; APP's items onto ENT, leaving every OTHER application's xdata alone.
;;
;; (entget ent) with no application list carries no xdata at all in
;; AutoCAD, so there this is the plain append the rest of the tree
;; writes.  The VM the tests run on hands back every group it holds,
;; xdata included, so the -3 already there is merged with rather than
;; doubled -- an entity cannot carry two of them, and assoc would only
;; ever find the first.
(defun g2m:xput (ent app items / ed x apps)
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
(defun g2m:xdel (ent app / ed x apps)
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
(defun g2m:xget (ent app / x a)
  (setq x (assoc -3 (entget ent (list app))))
  (if x (setq a (assoc app (cdr x))))
  (if (and a (cdr a)) (cdr a))
)

;; LST with its first N items dropped.
(defun g2m:tail (lst n)
  (while (and lst (> n 0)) (setq lst (cdr lst) n (1- n)))
  lst
)

;;; -------------------- the annotative flag ------------------------------
;; AutoCAD writes it as
;;
;;     1001 AcadAnnotative  1000 AnnotativeData  1002 {
;;     1070 <class>  1070 <flag>  1002 }
;;
;; so the flag is the SECOND 1070 in the block.  The first is the
;; block's own class number and rewriting it would not turn anything
;; off, it would make the block unreadable.

;; ENT's annotative flag, or -1 when it carries no such block at all.
(defun g2m:anno-flag (ent / items seen out it)
  (setq items (g2m:xget ent *g2mconv-anno-xdata*)
        seen  0
        out   -1)
  (foreach it items
    (if (= 1070 (car it))
      (progn
        (setq seen (1+ seen))
        (if (= 2 seen) (setq out (cdr it))))))
  out)

;; ITEMS with the second 1070 in them set to N.
(defun g2m:set-anno-items (items n / out seen it)
  (setq out '() seen 0)
  (foreach it items
    (if (= 1070 (car it)) (setq seen (1+ seen)))
    (setq out (cons (if (and (= 1070 (car it)) (= 2 seen))
                      (cons 1070 n)
                      it)
                    out)))
  (reverse out))

;; ENT's annotative flag set to N -- a no-op on an object that has no
;; such block, which is most of them.
(defun g2m:put-anno-flag (ent n / items)
  (if (setq items (g2m:xget ent *g2mconv-anno-xdata*))
    (progn
      (regapp *g2mconv-anno-xdata*)
      (g2m:xput ent *g2mconv-anno-xdata* (g2m:set-anno-items items n))))
)

;;; -------------------- the two restyles ---------------------------------

;; One dimension onto the shop style, overrides and all.  The style name
;; is DXF group 3 and can simply be written; the overrides come off
;; through g2m:xdel, which deletes ONE application's xdata and leaves
;; every other application's where it is -- this file's own record
;; among them, since it is written before this runs.
(defun g2m:restyle-dim (ent style app)
  (if (assoc 3 (entget ent)) (g2m:put-group ent 3 style))
  (if app (g2m:xdel ent app))
  (entupd ent))

;; One note onto the shop text style and height.  Both or neither: a
;; height is measured for the style it is set in.  The MTEXT box is
;; left to AutoCAD, which recomputes it from the new style's own
;; letters -- setting it here would be guessing at a font's metrics.
(defun g2m:restyle-text (ent style height / obj)
  (setq obj (vlax-ename->vla-object ent))
  (vla-put-StyleName obj style)
  (if height (vla-put-Height obj height))
  (entupd ent))

;;; -------------------- the record --------------------------------------
;; Thirteen xdata items in a fixed order, and then -- for a dimension --
;; the export's own override block copied straight in behind them.
;; xdata groups are typed, so there is no grammar here to get wrong: a
;; layer name carrying a "|" (an xref-dependent one does) travels as
;; itself, and the overrides travel as the xdata items they already
;; are rather than as a rendering of them.
;;
;;    0  1000  "G2MCONV"               the marker
;;    1  1000  the version that wrote it
;;    2  1000  the layer it came off
;;    3  1000  its linetype, before the appearance step
;;    4  1000  its dimension style, "" for anything but a dimension
;;    5  1000  its text style,      "" for anything but a note
;;    6  1070  that layer's own colour, for a source layer since PURGEd
;;    7  1070  its colour,     before the forcing
;;    8  1070  its lineweight, before the forcing
;;    9  1070  its annotative flag, -1 when it carried no such block
;;   10  1040  its linetype scale, 1.0 when it carried no such group
;;   11  1040  its text height,    0.0 for anything but a note
;;   12  1070  1 when an override block follows, else 0
;;   13+       that block, item for item, braces and all
;;
;; The block is already brace-balanced where it stands, so it needs no
;; wrapper of its own -- and must not be given one, because AutoCAD
;; refuses xdata whose braces do not balance.

;; NOT A KNOB: the number of items in the fixed part above, which
;; g2m:read indexes into and after which the override block starts.
;; Changing it does not change the record's shape, it stops the reader
;; agreeing with the writer.
(setq *g2mconv-record-len* 13)

;; The colour to re-create a source layer with, read off the layer
;; while it is still there.  A layer that is switched OFF carries the
;; colour negated; the record keeps the colour and not the off-ness, so
;; a layer G2MRECONV has to re-create comes back visible.
(defun g2m:layer-color (name / tb c)
  (setq tb (tblsearch "LAYER" name)
        c  (if tb (cdr (assoc 62 tb))))
  (if (and c (/= c 0)) (abs c) *g2mconv-default-color*)
)

;; Written BEFORE the move and before either restyle, which is the only
;; moment the object still carries everything the record is about.
(defun g2m:stamp (ent lay / obj typ sty ovr tsty thgt)
  (regapp *g2mconv-xdata-app*)
  (setq obj (vlax-ename->vla-object ent)
        typ (cdr (assoc 0 (entget ent))))
  ;; only a DIMENSION has a style to lose or overrides to lose it to,
  ;; and group 3 means something else entirely on an MTEXT
  (if (= "DIMENSION" typ)
    (setq sty (cdr (assoc 3 (entget ent)))
          ovr (if *g2mconv-dim-xdata* (g2m:xget ent *g2mconv-dim-xdata*))))
  ;; and only a note has a text style and height to lose
  (if (g2m:text-p typ)
    (setq tsty (vla-get-StyleName obj)
          thgt (vla-get-Height obj)))
  (g2m:xput ent *g2mconv-xdata-app*
    (append (list (cons 1000 *g2mconv-xdata-app*)
                  (cons 1000 *g2mconv-version*)
                  (cons 1000 lay)
                  (cons 1000 (vla-get-Linetype obj))
                  (cons 1000 (if sty sty ""))
                  (cons 1000 (if tsty tsty ""))
                  (cons 1070 (g2m:layer-color lay))
                  (cons 1070 (vla-get-Color obj))
                  (cons 1070 (vla-get-Lineweight obj))
                  (cons 1070 (g2m:anno-flag ent))
                  (cons 1040 (float (g2m:group ent 48 1.0)))
                  (cons 1040 (if thgt (float thgt) 0.0))
                  (cons 1070 (if ovr 1 0)))
            (if ovr ovr '())))
)

;; (source-layer layer-colour colour linetype lineweight dim-style
;;  text-style text-height ltscale anno-flag overrides) off one object,
;; or nil when it carries no record of ours.
(defun g2m:read (ent / items)
  (setq items (g2m:xget ent *g2mconv-xdata-app*))
  (if (and items
           (<= *g2mconv-record-len* (length items))
           (= *g2mconv-xdata-app* (cdr (nth 0 items))))
    (list (cdr (nth 2 items))
          (cdr (nth 6 items))
          (cdr (nth 7 items))
          (cdr (nth 3 items))
          (cdr (nth 8 items))
          (cdr (nth 4 items))
          (cdr (nth 5 items))
          (cdr (nth 11 items))
          (cdr (nth 10 items))
          (cdr (nth 9 items))
          (if (= 1 (cdr (nth 12 items)))
            (g2m:tail items *g2mconv-record-len*))))
)

;; The colour to re-create source layer LAY with: the one the record
;; kept from the layer itself, off the first object that came off it.
;; An existing layer is never recoloured -- ensure-layer only ever uses
;; this when the layer has to be made -- so a drawing that still has
;; its export layers keeps their colours whatever the record says.
(defun g2m:color-for (lay recs / out r)
  (foreach r recs
    (if (and (null out) (= (strcase (nth 1 r)) (strcase lay)))
      (setq out (nth 2 r))))
  (if out out *g2mconv-default-color*)
)

;; Every (ename . record) in SS, in drawing order.
(defun g2m:recorded (ss / i ent rec out)
  (setq i 0 out '())
  (while (< i (sslength ss))
    (setq ent (ssname ss i))
    (if (and (entget ent) (setq rec (g2m:read ent)))
      (setq out (cons (cons ent rec) out)))
    (setq i (1+ i)))
  (reverse out)
)

;;; -------------------- the plan ----------------------------------------

;; Work out what moves where WITHOUT touching anything, so the run can
;; ask for exactly the layers it needs and can say up front that a
;; drawing has nothing to convert.  Returns
;;
;;     (jobs source-layers destination-layers tally)
;;
;; where jobs is a list of (ename . rule) in drawing order -- the WHOLE
;; rule, so the appearance columns cannot come from a different row
;; than the destination did.  An object a rule sends to the layer it is
;; already on is not a job.
(defun g2m:plan (ss / i ent ed typ lay rule dest jobs srcs dests tally)
  (setq i 0)
  (while (< i (sslength ss))
    (setq ent  (ssname ss i)
          ed   (entget ent)
          typ  (cdr (assoc 0 ed))
          lay  (cdr (assoc 8 ed))
          rule (g2m:rule typ lay)
          dest (if rule (caddr rule)))
    (if (and dest (/= (strcase lay) (strcase dest)))
      (setq jobs  (cons (cons ent rule) jobs)
            srcs  (g2m:add lay srcs)
            dests (g2m:add dest dests)
            tally (g2m:bump dest tally)))
    (setq i (1+ i)))
  (list (reverse jobs) srcs dests tally))

;; The scope both commands take: the highlight if there is one, else
;; what is picked at the prompt, else the whole drawing.  An export
;; usually IS the whole drawing, which is why Enter means that;
;; highlight first when two plans share one sheet.
(defun g2m:scope (msg / ss)
  (setq ss (ssget "_I"))
  (if lzd:watch (lzd:watch ss))
  (if (null ss)
    (progn
      (prompt (strcat "\n" msg " <Enter = whole drawing>: "))
      (setq ss (ssget))
      (if lzd:watch (lzd:watch ss))
      (if (null ss) (setq ss (ssget "_X")))))
  ss)

;;; -------------------- the command -------------------------------------
(defun c:G2MCONV (/ *error* doc unlocked mark-open ss plan jobs srcs dests
                    tally job rule dest ent obj typ dims notes lt
                    missing-lt no-dimstyle no-textstyle)

  ;; The handler is LOCAL to this command (STANDARDS 5): a handler
  ;; installed in the global *error* is the handler of whatever runs
  ;; next the first time a run ends without putting it back.  It sees
  ;; doc / unlocked / mark-open through dynamic scope, and closes only
  ;; the mark this run opened -- the close can itself throw when the
  ;; failure came before StartUndoMark, and a throw inside *error* is
  ;; the one error nothing can catch.
  (defun *error* (msg)
    ;; locked layers come back FIRST so nothing below can skip them
    (if unlocked (vl-catch-all-apply 'g2m:relock-layers (list unlocked)))
    (setq unlocked nil)
    (if mark-open (vl-catch-all-apply 'vla-EndUndoMark (list doc)))
    (setq mark-open nil)
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nG2MCONV error: " msg)))
    (if lzd:report (lzd:report "G2MCONV" *g2mconv-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "G2MCONV" *g2mconv-version*))

  (setq doc      (vla-get-ActiveDocument (vlax-get-acad-object))
        unlocked nil
        dims     '()
        notes    '()
        missing-lt '())

  (vla-StartUndoMark doc)
  (setq mark-open T)

  (setq ss    (g2m:scope "Select the G2M export to convert")
        plan  (if ss (g2m:plan ss) '(nil nil nil nil))
        jobs  (car plan)
        srcs  (cadr plan)
        dests (caddr plan)
        tally (cadddr plan))

  (if jobs
    (progn
      ;; only the destinations this run actually reaches -- an export
      ;; with no dimensions in it does not want an empty DIMENSION
      ;; layer created for it
      (foreach dest dests
        (cal:ensure-layer dest (g2m:color dest)))
      ;; unlock everything about to be touched, both ends of the move
      (setq unlocked (g2m:unlock-layers (append srcs dests) doc))

      (foreach job jobs
        (setq ent  (car job)
              rule (cdr job)
              typ  (cdr (assoc 0 (entget ent))))
        ;; the record first: after the move and the restyles the object
        ;; no longer carries any of what the record is about
        (if *g2mconv-record* (g2m:stamp ent (g2m:layer-of ent)))
        (setq obj (vlax-ename->vla-object ent))
        ;; 1. the layer, and the appearance that has to follow it
        (vla-put-Layer obj (caddr rule))
        (if *g2mconv-force-bylayer*
          (progn
            (vla-put-Color obj acByLayer)
            (vla-put-Lineweight obj acLnWtByLayer)))
        (if (setq lt (cadddr rule))
          (if (g2m:ltype-usable-p lt)
            (vla-put-Linetype obj lt)
            (setq missing-lt (g2m:add lt missing-lt))))
        (if (nth 4 rule) (g2m:put-group ent 48 (float (nth 4 rule))))
        ;; 2. and 3. are collected rather than done here: both need a
        ;; table lookup that is the same answer for every object, and
        ;; the message about a missing style is one line, not one
        ;; per dimension
        (if (= "DIMENSION" typ) (setq dims  (cons ent dims)))
        (if (g2m:text-p typ)    (setq notes (cons ent notes)))
        (if *g2mconv-deannotate* (g2m:put-anno-flag ent 0)))

      ;; 2. the notes
      (if notes
        (if (and *g2mconv-text-style*
                 (tblsearch "STYLE" *g2mconv-text-style*))
          (foreach ent (reverse notes)
            (g2m:restyle-text ent *g2mconv-text-style*
                              *g2mconv-text-height*))
          (setq no-textstyle T)))
      ;; 3. the dimensions
      (if dims
        (if (tblsearch "DIMSTYLE" *g2mconv-dim-style*)
          (foreach ent (reverse dims)
            (g2m:restyle-dim ent *g2mconv-dim-style* *g2mconv-dim-xdata*))
          (setq no-dimstyle T)))

      (g2m:relock-layers unlocked)
      (setq unlocked nil)))

  (vla-EndUndoMark doc)
  (setq mark-open nil)

  (if jobs
    (progn
      (princ (strcat "\nG2MCONV done: " (itoa (length jobs))
                     " object(s) moved -- " (g2m:tally-line tally) "."))
      (if notes
        (princ (strcat "\n  " (itoa (length notes)) " note(s) "
                       (if no-textstyle
                         (strcat "kept the export's text style - this"
                                 " drawing has no \"" *g2mconv-text-style*
                                 "\" style, and a height belongs with the"
                                 " style it was set in.")
                         (strcat "restyled to " *g2mconv-text-style* " at "
                                 (rtos *g2mconv-text-height* 2 2) ".")))))
      (if dims
        (princ (strcat "\n  " (itoa (length dims)) " dimension(s) "
                       (if no-dimstyle
                         (strcat "kept the export's style and overrides -"
                                 " this drawing has no \""
                                 *g2mconv-dim-style* "\" dimension style.")
                         (strcat "put on " *g2mconv-dim-style*
                                 ", style overrides removed.")))))
      (if missing-lt
        (princ (strcat "\n  Linetype " (g2m:namelist missing-lt)
                       " is not loaded - those objects kept the linetype"
                       " they arrived with.  Load it and run again.")))
      (princ (strcat "\n  Moved off " (g2m:namelist srcs)
                     " - PURGE those layers once the result looks right."))
      (if *g2mconv-record*
        (princ "\n  G2MRECONV moves it all back; PURGE only when you are sure.")
        (princ (strcat "\n  *g2mconv-record* is off, so nothing was written"
                       " down - only U undoes this run."))))
    (progn
      (princ "\nG2MCONV: nothing here is on the export's layers - nothing moved.")
      (princ (strcat "\n  It converts " (g2m:namelist (g2m:sources))
                     "."))))
  (princ))

(defun c:G2MRECONV (/ *error* doc unlocked mark-open ss recs r ent obj
                      lay srcs offs missing done n)

  ;; G2MCONV's handler, for the same reasons (STANDARDS 5).
  (defun *error* (msg)
    (if unlocked (vl-catch-all-apply 'g2m:relock-layers (list unlocked)))
    (setq unlocked nil)
    (if mark-open (vl-catch-all-apply 'vla-EndUndoMark (list doc)))
    (setq mark-open nil)
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nG2MRECONV error: " msg)))
    (if lzd:report (lzd:report "G2MRECONV" *g2mconv-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "G2MRECONV" *g2mconv-version*))

  (setq doc      (vla-get-ActiveDocument (vlax-get-acad-object))
        unlocked nil
        missing  '()
        n        0)

  (vla-StartUndoMark doc)
  (setq mark-open T)

  ;; The scope G2MCONV takes, taken the same way.  Only objects
  ;; carrying a record move either way, so Enter is as safe here as it
  ;; is there.
  (setq ss   (g2m:scope "Select the converted export to put back")
        recs (if ss (g2m:recorded ss)))

  (if recs
    (progn
      ;; the layers it goes back ONTO, and the layers it comes OFF.
      ;; A destination of the revert is an output layer, so it is
      ;; created when the conversion's own PURGE advice was taken --
      ;; with the colour the record kept from the layer itself.
      (setq srcs '() offs '())
      (foreach r recs
        (setq lay  (nth 1 r)
              srcs (g2m:add lay srcs)
              offs (g2m:add (g2m:layer-of (car r)) offs)))
      (foreach lay srcs
        (cal:ensure-layer lay (g2m:color-for lay recs)))
      (setq unlocked (g2m:unlock-layers (append srcs offs) doc))

      (foreach r recs
        (setq ent  (car r)
              obj  (vlax-ename->vla-object ent)
              done T)
        (vla-put-Layer obj (nth 1 r))
        (vla-put-Color obj (nth 3 r))
        (vla-put-Lineweight obj (nth 5 r))
        (g2m:put-group ent 48 (nth 9 r))
        (if (or (member (strcase (nth 4 r)) '("BYLAYER" "BYBLOCK"))
                (tblsearch "LTYPE" (nth 4 r)))
          (vla-put-Linetype obj (nth 4 r))
          (setq missing (g2m:add (strcat "linetype " (nth 4 r)) missing)
                done    nil))
        ;; the text style and height, when it was a note.  Both or
        ;; neither, the way the conversion took them.
        (if (/= "" (nth 7 r))
          (if (tblsearch "STYLE" (nth 7 r))
            (progn
              (vla-put-StyleName obj (nth 7 r))
              (vla-put-Height obj (nth 8 r)))
            (setq missing (g2m:add (strcat "text style " (nth 7 r)) missing)
                  done    nil)))
        ;; the dimension style, and the override block behind it
        (if (/= "" (nth 6 r))
          (progn
            (if (tblsearch "DIMSTYLE" (nth 6 r))
              (g2m:put-group ent 3 (nth 6 r))
              (setq missing (g2m:add (strcat "dimension style " (nth 6 r))
                                     missing)
                    done    nil))
            (if (and (nth 11 r) *g2mconv-dim-xdata*)
              (progn
                (regapp *g2mconv-dim-xdata*)
                (g2m:xput ent *g2mconv-dim-xdata* (nth 11 r))))))
        ;; the annotative flag, when it had one
        (if (/= -1 (nth 10 r)) (g2m:put-anno-flag ent (nth 10 r)))
        (entupd ent)
        ;; The record goes with the move it described -- but only when
        ;; the move is FINISHED.  An object whose linetype or style is
        ;; no longer in the drawing keeps its record, so putting that
        ;; back and running again finishes the job instead of finding
        ;; nothing left to do.
        (if done
          (progn
            (g2m:xdel ent *g2mconv-xdata-app*)
            (setq n (1+ n)))))

      (g2m:relock-layers unlocked)
      (setq unlocked nil)))

  (vla-EndUndoMark doc)
  (setq mark-open nil)

  (if recs
    (progn
      (princ (strcat "\nG2MRECONV done: " (itoa (length recs))
                     " object(s) put back on " (g2m:namelist srcs) "."))
      (if missing
        (princ (strcat "\n  This drawing has no " (g2m:namelist missing)
                       ", so " (itoa (- (length recs) n))
                       " object(s) kept their record - put it back and run"
                       " G2MRECONV again to finish them."))))
    (princ "\nG2MRECONV: nothing here carries a G2MCONV record - nothing moved."))
  (princ))

(defun c:G2MCONVVER ()
  (princ (strcat "\nG2MCONV " *g2mconv-version*))
  (princ))

(princ (strcat "\nG2MCONV " *g2mconv-version*
               " loaded.  Type G2MCONV to run, G2MRECONV to undo."))
(princ)
