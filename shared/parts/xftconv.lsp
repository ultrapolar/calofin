;;; ===================================================================
;;;  XFTCONV.lsp   -  survey import cleanup (Leica XFT / site trace)
;;;  AutoCAD 2018
;;;
;;;  Command:  XFTCONV   - highlight the import, that is the only answer
;;;                        it needs
;;;
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;
;;;  Two exports arrive in feet and mark their points differently, and
;;;  XFTCONV reads both in the one pass - whichever it finds in the
;;;  selection is the one it acts on:
;;;
;;;    Leica XFT     an X of 2 crossing LINEs on layer LEICA_POINT (a
;;;                  POINT on that layer works too), with the point name
;;;                  as TEXT / MTEXT on LEICA_POINT_NAME, stacked above
;;;                  the marker
;;;    site trace    a small CIRCLE on POOL_POINTS, BREAK_LINES or
;;;                  CROSS_MEASUREMENTS, with the point name as TEXT
;;;                  sitting ON the circle's centre.  A corner carries
;;;                  two circles - one on POOL_POINTS, one on
;;;                  CROSS_MEASUREMENTS where a diagonal ends - and the
;;;                  pair collapses into the single block the location
;;;                  deserves.
;;;
;;;  What it does, to the objects you highlight:
;;;    1. scales the whole selection by 12 (feet -> inches), about the
;;;       middle of everything highlighted
;;;    2. finds every point marker of either flavour in the selection
;;;    3. replaces each one with an "ab_pt" block on layer POINTS,
;;;       attribute "number" set to the point number with the letter
;;;       prefix stripped ("P22" -> "22", "C1" -> "1")
;;;    4. erases the old marker and the name text it used
;;;    5. erases every other TEXT / MTEXT left in the selection - but
;;;       only for the Leica flavour, whose text is nothing but point
;;;       names.  A site trace labels its own break lines and diagonals
;;;       ("Deep End", "Diagonal 1"), so a blanket purge there would
;;;       throw the survey's annotation away with the noise.
;;;
;;;  Non-text geometry is scaled and otherwise left alone.  The whole
;;;  run is one UNDO step - in a drawing that records undo, that is; with
;;;  UNDO Control set to None it runs without a group rather than dying
;;;  on the group it could not open.
;;; ===================================================================



(setq *xft-version* "v1.13") ; printed on load and at command start so a
                             ; support screenshot says which copy is loaded

;;; -------------------- tunables ----------------------------------------
;;; Everything the export or the template might want changed, all in one
;;; block; nothing settable lives anywhere else in this file.  Each says
;;; what CHANGING it does.  setq any of them after loading -- in a
;;; startup file, say -- and the next run reads the new value.

;; --- what happens to the whole selection ---------------------------

;; Scale factor applied to EVERYTHING highlighted, about the middle of
;; its bounding box, before any point is read.  12 is feet -> inches,
;; which is how both exports arrive.  1.0 skips the SCALE step entirely
;; (an import that is already in inches); any other factor is applied
;; as given.  Every distance below that is NOT counted in text heights
;; is measured AFTER this scale, in drawing units.
(setq *xft-scale* 12.0)

;; --- the block every marker becomes ---------------------------------

;; The block that replaces each marker: the template's point block, the
;; one ABHD, POINTRENAMER and the rest of the build read.  If it is
;; missing from the drawing (a bare DXF rather than the template),
;; xft:ensure-block builds a copy - a POINT at the origin plus the
;; attribute below - and says so.  That fallback definition is written
;; to match the template and is not a setting.
(setq *xft-block* "ab_pt")

;; The layer the block is inserted on.  Created if missing; thawed,
;; unlocked and switched on if it is there but unusable (STANDARDS 5),
;; with a line saying so.  A LOCKED one is the exception: locks stop
;; the run by name before anything is touched, because the swap has to
;; erase as well as insert.
(setq *xft-block-layer* "POINTS")

;; The colour *xft-block-layer* is CREATED with when the drawing has
;; not got it.  An existing layer is never recoloured, so this only
;; ever shows on a bare drawing.  6 is magenta - the pink the survey
;; points show in, and the number SOCONV, VSCONV and DRONE create
;; POINTS with, so the converters agree on a bare drawing.
(setq *xft-block-layer-color* 6)

;; The attribute tag inside the block that receives the point number.
;; The template's ab_pt calls it "number", and every downstream tool
;; that labels points reads that tag - change it only with them.
(setq *xft-att-tag* "number")

;; The text style the attribute is written in.  If the drawing has no
;; style by this name the current TEXTSTYLE is used instead, quietly -
;; a missing style must not stop a conversion.
(setq *xft-att-style* "Attributes")

;; The attribute's text height, in drawing units AFTER the scale - 4.0
;; is what the sample drawing shows.  It is written into each ATTRIB,
;; so a fixed-height style does not change it.
(setq *xft-att-height* 4.0)

;; Where the attribute sits relative to the point: (dx dy) in drawing
;; units after the scale, as measured off the sample drawing - a little
;; right of and below the marker, so the number never sits on the dot.
(setq *xft-att-offset* '(0.8697246 -3.5316825))

;; --- the Leica XFT flavour ------------------------------------------
;; An X of two crossing LINEs (or a plain POINT) on *xft-marker-layer*,
;; with the name stacked above it as TEXT / MTEXT on *xft-name-layer*.

;; The layer the X markers sit on.  A wcmatch pattern - "*" and ","
;; work - so "LEICA_POINT,LEICA_PT" would read two exports' worth.
(setq *xft-marker-layer* "LEICA_POINT")

;; The layer the point-name text sits on.  Also a wcmatch pattern.  It
;; is tested BEFORE the marker layer, so a name layer whose name also
;; matches *xft-marker-layer* is still read as names, not markers.
(setq *xft-name-layer* "LEICA_POINT_NAME")

;; How far from a marker its name may sit, counted in that name's own
;; text heights (so the scale leaves it alone).  Leica stacks the name
;; a deliberate distance above the X - about 2.5 heights up - and the
;; layer already rules the rest of the drawing out, so six is generous
;; without reaching the next point over.
(setq *xft-name-reach* 6.0)

;; T takes the letter prefix off a Leica name: "P22" -> "22".  Leica
;; calls every point "P<n>", so the P is noise and nothing is lost.
;; nil puts the label in as it stands, MTEXT codes stripped and the
;; ends trimmed.  The site trace has its own switch below, and for a
;; reason given there, the opposite default.
(setq *xft-strip-prefix* T)

;; T erases every TEXT / MTEXT still in the selection once the swap is
;; done: a Leica export writes nothing but point names, so what is left
;; is import noise (including names that found no marker).  nil keeps
;; it.  Highlight only the import, or turn this off, when the selection
;; carries text you want.
(setq *xft-purge-text* T)

;; --- the site-trace flavour -----------------------------------------
;; Same feet, same block out the other end, but the marker is a small
;; CIRCLE instead of an X and it appears on three purpose layers rather
;; than one - POOL_POINTS for the pool corners, BREAK_LINES for the
;; shallow/deep breaks, CROSS_MEASUREMENTS for the ends of the
;; diagonals.  A corner is therefore drawn twice, once per layer;
;; xft:collect groups by location, so the two circles become one block.

;; The layers the circle markers sit on - a wcmatch comma list, so a
;; trace that adds a fourth point layer is one more name here.
(setq *xft-dot-layer* "POOL_POINTS,BREAK_LINES,CROSS_MEASUREMENTS")

;; The layer the trace writes its point names on.  It is the general
;; text layer, shared with the captions on its break lines and
;; diagonals ("Deep End", "Diagonal 1") - the reach below is what
;; tells the two apart, not the layer.
(setq *xft-dot-name-layer* "TEXT")

;; How far from a circle its name may sit, in text heights.  The name
;; sits ON the centre rather than above it, which is why this is one
;; height where the Leica reach is six: it only has to forgive an
;; exporter that nudges the label, and a tight reach is what keeps a
;; break line's own caption from being read as a point number.  Widen
;; it and "Deep End" - justified onto the middle of its break line, in
;; the same column as both of its endpoints - becomes a point.
(setq *xft-dot-reach* 1.0)

;; nil keeps a trace name whole: "C1" stays "C1".  The letter is the
;; point's family - C for a pool corner, S for a shallow-end break, D
;; for a deep-end one - and the numbers restart per family, so
;; stripping it would leave C1, S1 and D1 all reading "1": three points
;; wearing one number in the attribute every downstream tool labels
;; them from.  T strips it the way the Leica flavour does.
(setq *xft-dot-strip-prefix* nil)

;; nil leaves the trace's leftover text alone, because it is not all
;; point names: the break lines and the diagonals are captioned, and a
;; sweep would take the survey's annotation with the noise.  The name
;; text a point actually used is erased either way, in the swap.  T
;; sweeps, as the Leica flavour does.  A selection holding both
;; flavours - which no real import does - is swept if EITHER switch
;; is on, because the Leica half's noise is the reason to sweep.
(setq *xft-dot-purge-text* nil)

;; --- matching tolerances, both flavours -----------------------------

;; Both exports put the name in the marker's column - Leica stacks it
;; above, the trace lands it on the centre - so a name whose X is
;; within this many of its own text heights of the marker's X wins
;; over a name that is merely nearer.  That is what keeps a tight
;; cluster of points from stealing each other's tags.  Failing a
;; same-column name, nearest-within-reach wins; a name is used once.
(setq *xft-column-tol* 0.5)

;; How close two marker centres have to be, in drawing units after the
;; scale, to count as the same point.  The two LINEs of an X share an
;; exact midpoint and a corner's two circles an exact centre, so this
;; only has to absorb floating-point noise; widen it only if an export
;; starts landing its duplicate markers a measurable distance apart.
(setq *xft-fuzz* 1e-4)

(vl-load-com)   ; getboundingbox, for the middle of the selection


;;; -------------------- small helpers -----------------------------------

(defun xft:mid (a b)
  (list (/ (+ (car a) (car b)) 2.0)
        (/ (+ (cadr a) (cadr b)) 2.0)
        (/ (+ (caddr a) (caddr b)) 2.0)
  )
)

(defun xft:same (a b)                     ; same location within fuzz
  (< (cal:d2 a b) (* *xft-fuzz* *xft-fuzz*))
)

(defun xft:onlayer (ed pattern)
  (wcmatch (strcase (cdr (assoc 8 ed))) (strcase pattern))
)

;; strip the usual MTEXT formatting codes so "\A1;P22" comes back as "P22"
(defun xft:plain (s / out i c nxt n)
  (setq out "" i 1 n (strlen s))
  (while (<= i n)
    (setq c (substr s i 1))
    (cond
      ((= c "\\")
       (setq nxt (strcase (substr s (1+ i) 1)))
       (cond
         ((member nxt '("P" "X"))                 ; line break / paragraph
          (setq out (strcat out " ") i (+ i 2)))
         ((member nxt '("L" "O" "K"))             ; under/over/strike on-off
          (setq i (+ i 2)))
         ((wcmatch nxt "[ACFHQTW]")               ; codes closed by ";"
          (setq i (+ i 2))
          (while (and (<= i n) (/= (substr s i 1) ";")) (setq i (1+ i)))
          (setq i (1+ i)))
         (t (setq out (strcat out (substr s (1+ i) 1)) i (+ i 2)))
       )
      )
      ((member c '("{" "}")) (setq i (1+ i)))
      (t (setq out (strcat out c) i (1+ i)))
    )
  )
  out
)

;; "P22" -> "22"   "22" -> "22"   "STA" -> "STA"
(defun xft:number (s / i n c)
  (setq s (cal:trim (xft:plain s)) n (strlen s) i 1)
  (while (and (<= i n)
              (setq c (ascii (substr s i 1)))
              (or (< c 48) (> c 57)))
    (setq i (1+ i)))
  (if (<= i n) (substr s i) s)
)

;; where a text entity "sits".  a justified TEXT is really located at its
;; alignment point (11); on MTEXT group 11 is the direction vector, not a
;; point, so MTEXT always uses its insertion point (10).
(defun xft:txtpt (ed)
  (if (and (= "TEXT" (cdr (assoc 0 ed)))
           (assoc 11 ed)
           (or (/= 0 (cdr (assoc 72 (append ed '((72 . 0))))))
               (/= 0 (cdr (assoc 73 (append ed '((73 . 0))))))))
    (cdr (assoc 11 ed))
    (cdr (assoc 10 ed))
  )
)

;; centre of the box around everything that was highlighted.  ActiveX
;; getboundingbox is the only thing that knows the real extents of an arc,
;; a spline or a block, so it does the work; if it will not answer for an
;; object, that object's own definition points are used instead.
(defun xft:centre (ss / i en mn mx lo hi ed pair)
  (setq i 0 lo nil hi nil)
  (while (< i (sslength ss))
    (setq en (ssname ss i))
    (if (not (vl-catch-all-error-p
               (vl-catch-all-apply
                 '(lambda ()
                    (vla-getboundingbox (vlax-ename->vla-object en) 'mn 'mx)) '())))
      (setq lo (if lo (mapcar 'min lo (vlax-safearray->list mn)) (vlax-safearray->list mn))
            hi (if hi (mapcar 'max hi (vlax-safearray->list mx)) (vlax-safearray->list mx)))
      ;; fallback - whatever points the entity carries itself
      (progn
        (setq ed (entget en))
        (foreach pair ed
          (if (and (member (car pair) '(10 11))
                   (listp (cdr pair))
                   (= 3 (length (cdr pair))))
            (setq lo (if lo (mapcar 'min lo (cdr pair)) (cdr pair))
                  hi (if hi (mapcar 'max hi (cdr pair)) (cdr pair)))
          )
        )
      )
    )
    (setq i (1+ i))
  )
  (if (and lo hi)
    (mapcar '(lambda (a b) (/ (+ a b) 2.0)) lo hi)
    (list 0.0 0.0 0.0)
  )
)

;; add ename to the marker group at ctr, or start a new group
(defun xft:collect (groups ctr en / out hit)
  (setq out '() hit nil)
  (foreach g groups
    (if (and (not hit) (xft:same (car g) ctr))
      (setq out (cons (cons (car g) (cons en (cdr g))) out) hit t)
      (setq out (cons g out))
    )
  )
  (if hit (reverse out) (cons (list ctr en) groups))
)


;;; -------------------------------------------------------------------
;;;  drawing setup - make sure the layer, style and block are there
;;; -------------------------------------------------------------------

(defun xft:locked (lname / tb)
  (and (setq tb (tblsearch "LAYER" lname))
       (= 4 (logand 4 (cdr (assoc 70 tb)))))
)

;; Every locked layer that would be in the way, named so the message can
;; say which one to unlock: the layer of anything highlighted that the
;; swap has to erase, plus the block layer it inserts onto.  The
;; SELECTION is walked rather than the layer table because
;; *xft-dot-layer* is a comma list of three names and tblsearch takes
;; one name, no wildcards - and because a locked layer with nothing of
;; ours on it is not in the way at all.
(defun xft:locked-layers (ss / i lay pats out)
  (setq i    0
        out  '()
        pats (strcat (strcase *xft-marker-layer*) ","
                     (strcase *xft-name-layer*) ","
                     (strcase *xft-dot-layer*) ","
                     (strcase *xft-dot-name-layer*)))
  (while (< i (sslength ss))
    (setq lay (cdr (assoc 8 (entget (ssname ss i)))))
    (if (and (not (member (strcase lay) (mapcar 'strcase out)))
             (wcmatch (strcase lay) pats)
             (xft:locked lay))
      (setq out (cons lay out)))
    (setq i (1+ i))
  )
  (if (and (xft:locked *xft-block-layer*)
           (not (member (strcase *xft-block-layer*) (mapcar 'strcase out))))
    (setq out (cons *xft-block-layer* out)))
  (reverse out)
)

(defun xft:namelist (items / out s)          ; "A, B, C" for a message
  (setq out "")
  (foreach s items
    (setq out (if (= out "") s (strcat out ", " s))))
  out
)

(defun xft:style ()
  (if (tblsearch "STYLE" *xft-att-style*)
    *xft-att-style*
    (getvar "TEXTSTYLE")
  )
)

;; build ab_pt the same way the template has it, if it is missing
(defun xft:ensure-block ( / sty)
  (if (not (tblsearch "BLOCK" *xft-block*))
    (progn
      (setq sty (xft:style))
      (entmake (list '(0 . "BLOCK")
                     '(100 . "AcDbEntity")
                     '(8 . "0")
                     '(100 . "AcDbBlockBegin")
                     (cons 2 *xft-block*)
                     '(70 . 2)
                     '(10 0.0 0.0 0.0)
                     (cons 3 *xft-block*)
                     '(1 . "")))
      (entmake '((0 . "POINT")
                 (100 . "AcDbEntity")
                 (8 . "0")
                 (100 . "AcDbPoint")
                 (10 0.0 0.0 0.0)))
      (entmake (list '(0 . "ATTDEF")
                     '(100 . "AcDbEntity")
                     '(8 . "0")
                     '(100 . "AcDbText")
                     '(10 1.0 -2.0 0.0)
                     '(40 . 1.0)
                     '(1 . "0")
                     (cons 7 sty)
                     '(100 . "AcDbAttributeDefinition")
                     '(3 . "Type_Point_Number")
                     (cons 2 *xft-att-tag*)
                     '(70 . 4)))
      (entmake '((0 . "ENDBLK") (100 . "AcDbEntity") (8 . "0") (100 . "AcDbBlockEnd")))
      (princ (strcat "\n  block \"" *xft-block* "\" was not in this drawing - created it."))
    )
  )
  (tblsearch "BLOCK" *xft-block*)
)


;;; -------------------------------------------------------------------
;;;  insert one replacement point
;;; -------------------------------------------------------------------

(defun xft:insert (pt num / apt)
  (setq apt (list (+ (car pt) (car  *xft-att-offset*))
                  (+ (cadr pt) (cadr *xft-att-offset*))
                  (caddr pt)))
  (entmake (list '(0 . "INSERT")
                 '(100 . "AcDbEntity")
                 (cons 8 *xft-block-layer*)
                 '(100 . "AcDbBlockReference")
                 '(66 . 1)
                 (cons 2 *xft-block*)
                 (cons 10 pt)
                 '(41 . 1.0) '(42 . 1.0) '(43 . 1.0)
                 '(50 . 0.0)))
  (entmake (list '(0 . "ATTRIB")
                 '(100 . "AcDbEntity")
                 '(8 . "0")
                 '(100 . "AcDbText")
                 (cons 10 apt)
                 (cons 40 *xft-att-height*)
                 (cons 1 num)
                 (cons 7 (xft:style))
                 '(100 . "AcDbAttribute")
                 (cons 2 *xft-att-tag*)
                 '(70 . 0)))
  (entmake (list '(0 . "SEQEND")
                 '(100 . "AcDbEntity")
                 (cons 8 *xft-block-layer*)))
)


;;; -------------------------------------------------------------------
;;;  match markers to names, block in, marker out
;;; -------------------------------------------------------------------

;; GROUPS is ((centre ename ...) ...) from xft:collect, NAMES is
;; ((point string height ename used) ...), and REACH is how far from a
;; marker a name may sit, counted in that name's own text heights.
;;
;; Both exports put the name in the marker's column - the Leica one
;; stacks it above, the site trace lands it on the centre - so a name in
;; the same column (its X within *xft-column-tol* text heights of the
;; marker's) wins over a merely closer one.  That is what keeps a tight
;; cluster of points from stealing each other's tags.  Failing that,
;; nearest-within-reach wins, and a name is used once.
;;
;; STRIP says whether the name's letter prefix comes off ("P22" -> "22")
;; or the whole label goes in as it stands; either way MTEXT formatting
;; codes are stripped and the result is trimmed.
;;
;; Returns (made blank): how many blocks went in, and how many of those
;; found no name and carry a blank number.
(defun xft:swap (groups names reach strip / g nm ctr best bestd bestr rank
                                            txth lim d num made blank e)
  (setq made 0 blank 0)
  (foreach g groups
    (setq ctr   (car g)
          best  nil
          bestd nil
          bestr nil)
    (foreach nm names
      (if (not (nth 4 nm))
        (progn
          ;; a text with no height (or 0) still needs a reach: one unit
          (setq txth (if (and (nth 2 nm) (> (nth 2 nm) 0.0)) (nth 2 nm) 1.0)
                lim  (* reach txth)
                d    (cal:d2 ctr (car nm))
                rank (if (<= (abs (- (car (car nm)) (car ctr)))
                             (* *xft-column-tol* txth))
                       0 1))
          (if (and (< d (* lim lim))
                   (or (not best)
                       (< rank bestr)
                       (and (= rank bestr) (< d bestd))))
            (setq best nm bestd d bestr rank)
          )
        )
      )
    )
    (if best
      (setq num   (if strip
                    (xft:number (nth 1 best))
                    (cal:trim (xft:plain (nth 1 best))))
            names (subst (list (car best) (nth 1 best) (nth 2 best)
                               (nth 3 best) t)
                         best names))
      (setq num "" blank (1+ blank))
    )
    (xft:insert ctr num)
    (foreach e (cdr g) (entdel e))
    (if best (entdel (nth 3 best)))
    (setq made (1+ made))
  )
  (list made blank)
)


;;; -------------------------------------------------------------------
;;;  XFTCONV
;;; -------------------------------------------------------------------

(defun c:XFTCONV ( / *error* xft:restore oscm osos osclay undone guard
                     ss base i en ed typ locked
                     markers names dots dotnames r
                     nmade nblank ndots nleft)

  (defun xft:restore ()
    (if oscm   (setvar "CMDECHO" oscm))
    (if osos   (setvar "OSMODE"  osos))
    (if osclay (setvar "CLAYER"  osclay))
    ;; The error mode pushed below is popped HERE, on every way out --
    ;; the three quiet exits, the report, and the handler -- not in the
    ;; handler alone.  A clean run used to leave the mode stacked for
    ;; the rest of the session, and while it is stacked command-s is
    ;; refused inside every later handler (AutoLISP reference,
    ;; *push-error-using-command*), so the next tool's Esc left its
    ;; undo group open without a word.
    (if *pop-error-mode* (*pop-error-mode*))
  )

  (defun *error* (msg)
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nXFTCONV error: " msg)))
    ;; back out of SCALE etc.  Bounded: CMDACTIVE carries a
    ;; "dialog is up" bit no keystroke from here can clear, and an
    ;; unbounded drain against it would hang with no Esc out.
    (setq guard 0)
    (while (and (> (getvar "CMDACTIVE") 0) (< guard 10))
      (command)
      (setq guard (1+ guard)))
    (xft:restore)
    ;; through the catch: a throw here would strand the pop below, and
    ;; error mode would stay pushed for the rest of the session
    (if undone (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (princ "\nNothing was left half done - use U to roll the run back.")
    (princ)
  )

  ;; AutoCAD 2012+ requires this so *error* may call (command);
  ;; harmless no-op guard on older releases where it doesn't exist
  (if *push-error-using-command* (*push-error-using-command*))

  (setq oscm   (getvar "CMDECHO")
        osos   (getvar "OSMODE")
        osclay (getvar "CLAYER"))

  (princ (strcat "\nXFTCONV " *xft-version*
                 " - scale the survey and swap its points for blocks."))

  ;; ---- selection -------------------------------------------------
  ;; the only prompt there is.  the scale factor and the base point used
  ;; to be asked for, and the staged Back that moved between them went
  ;; with them - it is always x12 about the middle of the selection now,
  ;; so there is nothing left to step back to.  a selection made before
  ;; the command was typed (pickfirst) skips even that prompt.
  (setq ss (ssget "_I"))
  (if (not ss)
    (progn
      (princ "\nSelect the imported survey objects (Enter = everything in this space): ")
      (setq ss (ssget))))
  (if (not ss)
    (setq ss (ssget "_X" (list (cons 410 (getvar "CTAB")))))
  )

  (if (not ss)
    (progn (princ "\nNothing to work on.") (xft:restore) (princ))
    (progn

      ;; ---- locked layers would break the swap --------------------
      ;; only the ones actually in the way are named: entdel and entmake
      ;; both refuse a locked layer, and a layer nothing in the
      ;; selection sits on cannot stop the run.
      (setq locked (xft:locked-layers ss))
      (if locked
        (progn
          (princ (strcat "\nUnlock " (xft:namelist locked)
                         " first, then run XFTCONV again."))
          (xft:restore)
          (princ)
        )
        (progn

          (setvar "CMDECHO" 0)
          (setvar "OSMODE" 0)
          ;; only when undo is recording - _Begin in a drawing with UNDO
          ;; off (bit 1 of UNDOCTL clear) errors out of the command, and
          ;; so does the _End at the bottom, which is why both sit
          ;; behind the undone flag (the handler's close always did)
          (if (= 1 (logand 1 (getvar "UNDOCTL")))
            (progn
              (command "_.UNDO" "_Begin")
              (setq undone t)))

          ;; ---- 0. the layer and the block have to be there --------
          (cal:ensure-layer *xft-block-layer* *xft-block-layer-color*)
          (xft:ensure-block)

          ;; ---- 1. scale x12 about the middle of what was picked ---
          ;; getboundingbox works in WCS, SCALE wants the current UCS
          (setq base (trans (xft:centre ss) 0 1))
          (if (/= *xft-scale* 1.0)
            (progn
              (princ (strcat "\nScaling " (itoa (sslength ss)) " objects by "
                             (rtos *xft-scale* 2 4) " about the middle of the selection ..."))
              (command "_.SCALE" ss "" base *xft-scale*)
            )
          )

          ;; ---- 2. sort the selection into markers and names -------
          ;; the two flavours are kept apart rather than pooled: each
          ;; matches its markers against its OWN names, at its own
          ;; reach, so a site trace's captions can never be offered to a
          ;; Leica marker six text heights away.
          (setq markers '() names '() dots '() dotnames '() i 0)
          (while (< i (sslength ss))
            (setq en  (ssname ss i)
                  ed  (entget en)
                  typ (cdr (assoc 0 ed)))
            (cond
              ;; name text first - LEICA_POINT would also match its layer
              ((and (member typ '("TEXT" "MTEXT"))
                    (xft:onlayer ed *xft-name-layer*))
               (setq names (cons (list (xft:txtpt ed)
                                       (cdr (assoc 1 ed))
                                       (cdr (assoc 40 ed))
                                       en
                                       nil)
                                 names)))
              ;; the site trace writes its names on the general text
              ;; layer, alongside the captions - the tight reach in
              ;; xft:swap is what tells the two apart, not the layer
              ((and (member typ '("TEXT" "MTEXT"))
                    (xft:onlayer ed *xft-dot-name-layer*))
               (setq dotnames (cons (list (xft:txtpt ed)
                                          (cdr (assoc 1 ed))
                                          (cdr (assoc 40 ed))
                                          en
                                          nil)
                                    dotnames)))
              ;; the X marker - both lines share the same midpoint
              ((and (= typ "LINE") (xft:onlayer ed *xft-marker-layer*))
               (setq markers (xft:collect markers
                                          (xft:mid (cdr (assoc 10 ed)) (cdr (assoc 11 ed)))
                                          en)))
              ;; some exports drop a plain POINT instead
              ((and (= typ "POINT") (xft:onlayer ed *xft-marker-layer*))
               (setq markers (xft:collect markers (cdr (assoc 10 ed)) en)))
              ;; the site trace's circle.  Collecting by centre is what
              ;; merges the POOL_POINTS copy of a corner with the
              ;; CROSS_MEASUREMENTS one into a single block.
              ((and (= typ "CIRCLE") (xft:onlayer ed *xft-dot-layer*))
               (setq dots (xft:collect dots (cdr (assoc 10 ed)) en)))
            )
            (setq i (1+ i))
          )

          ;; ---- 3/4. name each marker, block in, marker out -------
          (setq r      (xft:swap markers names *xft-name-reach*
                                 *xft-strip-prefix*)
                nmade  (car r)
                nblank (cadr r))
          (setq r      (xft:swap dots dotnames *xft-dot-reach*
                                 *xft-dot-strip-prefix*)
                ndots  (car r)
                nmade  (+ nmade ndots)
                nblank (+ nblank (cadr r)))

          ;; ---- 5. every other bit of text in the selection goes ---
          ;; the numbers now live in the block attributes, so anything
          ;; still written as text is leftover import noise.  entget
          ;; comes back nil on what step 4 already erased, which keeps
          ;; entdel from toggling those back into the drawing.
          ;;
          ;; Per flavour, and off for the site trace: the Leica export
          ;; writes nothing but point names, so sweeping the rest is
          ;; the cleanup; the site trace captions its own break lines
          ;; and diagonals, so the same sweep would be vandalism.  A
          ;; selection holding both - which no real import does - is
          ;; swept, because the Leica half's noise is the whole reason
          ;; the setting is on by default.
          (setq nleft 0)
          (if (or (and markers *xft-purge-text*)
                  (and dots *xft-dot-purge-text*))
            (progn
              (setq i 0)
              (while (< i (sslength ss))
                (setq en (ssname ss i)
                      ed (entget en))
                (if (and ed (member (cdr (assoc 0 ed)) '("TEXT" "MTEXT")))
                  (progn (entdel en) (setq nleft (1+ nleft)))
                )
                (setq i (1+ i))
              )
            )
          )

          (if undone (command "_.UNDO" "_End"))
          (setq undone nil)
          (xft:restore)

          ;; ---- report --------------------------------------------
          (princ (strcat "\n"
                         (itoa nmade) " point(s) replaced with \"" *xft-block* "\"."))
          (if (> ndots 0)
            (princ (strcat "\n" (itoa ndots)
                           " of those were circle markers off a site trace ("
                           *xft-dot-layer* ").")))
          (if (> nblank 0)
            (princ (strcat "\n" (itoa nblank)
                           " had no name text nearby - inserted with a blank number.")))
          (if (> nleft 0)
            (princ (strcat "\n" (itoa nleft) " leftover text object(s) erased.")))
          (princ)
        )
      )
    )
  )
  (princ)
)


;;; -------------------------------------------------------------------
;;;  make sure the pieces exist as soon as the file loads
;;; -------------------------------------------------------------------

(defun c:XFTCONV-SETUP ()
  (cal:ensure-layer *xft-block-layer* *xft-block-layer-color*)
  (xft:ensure-block)
  (princ (strcat "\nLayer \"" *xft-block-layer* "\" and block \"" *xft-block* "\" are ready."))
  (princ)
)

(defun c:XFTCONVVER ()
  (princ (strcat "\nXFTCONV " *xft-version*))
  (princ))

(princ (strcat "\nXFTCONV.lsp " *xft-version*
               " loaded.  Type XFTCONV to scale a survey import and swap its points."))
(princ)
