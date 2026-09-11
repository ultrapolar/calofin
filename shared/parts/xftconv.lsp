;;; ===================================================================
;;;  XFTCONV.lsp   -  survey import cleanup (Leica XFT / site trace)
;;;  AutoCAD 2018
;;;
;;;  Commands:  XFTCONV    - highlight the import, that is the only
;;;                          answer it needs
;;;             XFTRECONV  - put a converted import back the way it
;;;                          arrived
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
;;;
;;;  XFTRECONV undoes all of it.  U undoes a run that is still in the
;;;  session; XFTRECONV undoes one that was saved and reopened a week
;;;  later, which is when a survey turns out to have been converted
;;;  twice or converted by mistake.  It can do that because XFTCONV
;;;  writes down what it erased: every block it inserts carries a
;;;  RECORD in its own xdata - the scale and the base point the run
;;;  used, and the marker, the name text and any leftover text that
;;;  went with them, group by group.  Erasing alone would not be
;;;  enough to work from: an entdel'd entity is gone for good once the
;;;  drawing is saved, and the scale factor is not written on anything.
;;;
;;;  So XFTRECONV rebuilds what the swap erased, erases the block that
;;;  replaced it, and scales the selection back by 1/12 about the same
;;;  base point - and a drawing that has been through both is the
;;;  drawing that arrived.  *xft-record* is the one line that turns the
;;;  record off; with it off XFTCONV still converts and XFTRECONV has
;;;  nothing to work from and says so.
;;; ===================================================================



(setq *xft-version* "v1.14") ; printed on load and at command start so a
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

;; --- the undo record XFTRECONV reads --------------------------------

;; T writes a record into each block's xdata as it goes in, and that
;; record is the only thing that lets XFTRECONV put the survey back
;; once the drawing has been saved and reopened (U undoes a run still
;; in the session).  nil converts exactly as this file did before the
;; record existed and writes nothing down, so the run can then be
;; undone by U and by nothing else.
(setq *xft-record* T)

;; The xdata application the record lives under.  Two drawings' records
;; cannot collide, so this only wants changing if a shop already uses
;; the name for something else; XFTRECONV reads whatever is set here,
;; so a drawing converted under one name is not readable under another.
(setq *xft-xdata-app* "XFTCONV")

;; Decimals a coordinate is written to in the record.  8 puts the round
;; trip within 1e-8 of a drawing unit -- a hundredth of a micron on a
;; survey in inches -- which is what tests/test_xftconv.py measures.
;; Fewer makes the rebuild coarser; more makes the record longer
;; without making it truer, the number having come from a float.
(setq *xft-num-prec* 8)

;; The colour a source layer is re-created with when XFTRECONV has to
;; rebuild one that was PURGED after the conversion.  A layer still in
;; the drawing keeps its own colour, as everywhere else in the build,
;; so this is only ever reached by a rebuild onto a layer that is gone.
(setq *xft-rebuild-color* 7)

;; Which DXF groups the record carries whatever the entity type is --
;; layer, colour, linetype, lineweight, and the space it sits in.
;; Dropping one here means XFTRECONV cannot put that property back.
(setq *xft-keep-common* '(8 62 6 370 410))

;; And the groups it carries per type: what an export writes on the
;; five kinds of object XFTCONV erases.  An export that writes
;; something else onto its markers -- a thickness, a transparency -- is
;; carried by adding its group code to the right row, and nothing else
;; in the file changes.  A code is read back as a point (10, 11), a
;; real (39 40 41 50 51), an integer (62 66 70-73 370) or a string, by
;; xft:group, so a code of a kind not in one of those four lists comes
;; back as text.
(setq *xft-keep*
  '(("LINE"   (10 11))
    ("POINT"  (10 50))
    ("CIRCLE" (10 40))
    ("TEXT"   (1 7 10 11 40 41 50 51 71 72 73))
    ("MTEXT"  (1 3 7 10 40 41 50 71 72))))

(vl-load-com)   ; getboundingbox, for the middle of the selection


;;; -------------------------------------------------------------------
;;;  small helpers
;;; -------------------------------------------------------------------

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
;;;  the record - what XFTRECONV puts the survey back from
;;; -------------------------------------------------------------------
;;;  One string per block, in that block's own xdata.  It holds the
;;;  entities the swap erased, written out group by group, and beside
;;;  it as xdata reals the scale and the base point the run used - the
;;;  two numbers no object in the drawing carries.
;;;
;;;  The grammar is one line: entities are separated by ";", their
;;;  groups by "|", a group's code from its value by "=", and the parts
;;;  of a point by ",".  Any of those - and the "\" that escapes them,
;;;  which MTEXT formatting is full of - is backslash-escaped inside a
;;;  value, so the string can be split a level at a time and a caption
;;;  reading "1=2;3" is never read as structure.  Escapes come off at
;;;  the leaf and nowhere earlier, which is why xft:split leaves them
;;;  on.
;;;
;;;  Coordinates go through rtos at *xft-num-prec* decimals rather than
;;;  as raw floats, because xdata carries strings and reals in separate
;;;  groups and one string keeps the record readable in a DXF dump.  A
;;;  round trip is therefore exact to 1e-8 of a drawing unit - a
;;;  hundredth of a micron on a survey in inches - and not to the last
;;;  bit of the float.  tests/test_xftconv.py measures exactly that, so
;;;  the claim cannot rot.
;;;
;;;  Only the groups a rebuild needs are carried: what an export writes
;;;  on the five entity types XFTCONV erases.  An object's own xdata,
;;;  its extension dictionary and its reactors are NOT in the record and
;;;  do not come back - a survey import has none, and inventing a
;;;  general entity copier here would be claiming more than the tool
;;;  can test.

;; NOT A KNOB: these five characters are the grammar itself, and
;; xft:esc, xft:split and xft:unesc all read this list -- but changing
;; it changes what an ALREADY WRITTEN record means, so a drawing
;; converted before the change could not be read after it.  The list is
;; here so the three helpers cannot disagree about it, not so it can be
;; edited.  (Which groups the record carries IS tunable: *xft-keep* is
;; in the block at the top.)
(setq *xft-delims* '("\\" ";" "|" "=" ","))

;; NOT A KNOB: AutoCAD's own subclass names, which entmake wants and
;; will not accept a substitute for.  A type is added here when it is
;; added to *xft-keep*; neither name in a row is a choice.
(setq *xft-subclass*
  '(("LINE"   "AcDbLine")
    ("POINT"  "AcDbPoint")
    ("CIRCLE" "AcDbCircle")
    ("TEXT"   "AcDbText")
    ("MTEXT"  "AcDbMText")))

(defun xft:esc (s / i n c out)
  (setq out "" i 1 n (strlen s))
  (while (<= i n)
    (setq c   (substr s i 1)
          out (strcat out (if (member c *xft-delims*) (strcat "\\" c) c))
          i   (1+ i)))
  out
)

(defun xft:unesc (s / i n c out)
  (setq out "" i 1 n (strlen s))
  (while (<= i n)
    (setq c (substr s i 1))
    (if (and (= c "\\") (< i n))
      (setq out (strcat out (substr s (1+ i) 1)) i (+ i 2))
      (setq out (strcat out c) i (1+ i))))
  out
)

;; S split on every UNESCAPED sep.  The pieces keep their escapes -
;; take them off with xft:unesc at the leaf, or a value that escaped a
;; "=" would be split on it at the next level down.
(defun xft:split (s sep / i n c out cur)
  (setq out '() cur "" i 1 n (strlen s))
  (while (<= i n)
    (setq c (substr s i 1))
    (cond
      ((and (= c "\\") (< i n))
       (setq cur (strcat cur c (substr s (1+ i) 1)) i (+ i 2)))
      ((= c sep) (setq out (cons cur out) cur "" i (1+ i)))
      (t (setq cur (strcat cur c) i (1+ i)))
    )
  )
  (reverse (cons cur out))
)

(defun xft:atof (s) (if s (atof s) 0.0))

(defun xft:r2s (v) (rtos v 2 *xft-num-prec*))

;; A DXF value as text: a point is its three parts, a number is rtos'd
;; or itoa'd, a string is itself.
;;
;; ESCAPING HAPPENS HERE, on the leaves, and nowhere above.  A point
;; writes the "," between its parts itself, so a caller that escaped
;; the whole result afterwards would escape that comma too -- and the
;; split that reads it back, which only cuts on an UNESCAPED one, would
;; hand the whole "x,y,z" back as the x and read the y as zero.  Only a
;; string can carry a delimiter, so only a string is escaped.
(defun xft:val2s (v)
  (cond
    ((null v) "")
    ((= (type v) 'LIST)
     (strcat (xft:r2s (car v)) "," (xft:r2s (cadr v)) ","
             (xft:r2s (if (caddr v) (caddr v) 0.0))))
    ((= (type v) 'STR) (xft:esc v))
    ((= (type v) 'INT) (itoa v))
    (t (xft:r2s v))
  )
)

;; ...and back, the CODE saying which of the four it was.  S is still
;; escaped, so a point is split before its parts are unescaped.
(defun xft:group (code s / b)
  (cond
    ((member code '(10 11))
     (setq b (mapcar 'xft:unesc (xft:split s ",")))
     (cons code (list (xft:atof (car b)) (xft:atof (cadr b))
                      (xft:atof (caddr b)))))
    ((member code '(39 40 41 50 51)) (cons code (xft:atof (xft:unesc s))))
    ((member code '(62 66 70 71 72 73 370)) (cons code (atoi (xft:unesc s))))
    (t (cons code (xft:unesc s)))
  )
)

;; One entity as one string, nil for a type the record does not carry.
;; The alist is walked in ORDER rather than assoc'd group by group, so
;; an MTEXT that spills its text across repeated group 3s keeps all of
;; them.
(defun xft:ser (en / ed typ codes p out)
  (setq ed  (entget en)
        typ (cdr (assoc 0 ed)))
  (if (setq codes (cadr (assoc typ *xft-keep*)))
    (progn
      (setq codes (append codes *xft-keep-common*)
            out   (strcat "0=" (xft:esc typ)))
      (foreach p ed
        (if (member (car p) codes)
          (setq out (strcat out "|" (itoa (car p)) "="
                            (xft:val2s (cdr p))))))
      out
    )
  )
)

(defun xft:deser (spec / g bits ed)
  (setq ed '())
  (foreach g (xft:split spec "|")
    (setq bits (xft:split g "="))
    (if (cdr bits)
      (setq ed (cons (xft:group (atoi (xft:unesc (car bits))) (cadr bits))
                     ed))))
  (reverse ed)
)

;; SPEC back into the drawing, or nil when it names a type the record
;; does not carry.  The layer goes through ensure-layer: it is an output
;; layer for this run, and a rebuild onto one that was PURGED after the
;; conversion has to create it (STANDARDS 5).
(defun xft:rebuild (spec / ed typ sub lay out p)
  (setq ed  (xft:deser spec)
        typ (cdr (assoc 0 ed))
        sub (cadr (assoc typ *xft-subclass*))
        lay (cdr (assoc 8 ed)))
  (if (and typ sub)
    (progn
      (cal:ensure-layer (if lay lay "0") *xft-rebuild-color*)
      (setq out (list (cons 0 typ) '(100 . "AcDbEntity")))
      (foreach p ed
        (if (member (car p) *xft-keep-common*)
          (setq out (append out (list p)))))
      (setq out (append out (list (cons 100 sub))))
      (foreach p ed
        (if (not (member (car p) (cons 0 *xft-keep-common*)))
          (setq out (append out (list p)))))
      (entmakex out)
    )
  )
)

;; SPEC appended to a payload, "" and nil both meaning nothing to add.
(defun xft:join (payload spec)
  (cond
    ((or (null spec) (= spec "")) payload)
    ((= payload "") spec)
    (t (strcat payload ";" spec))
  )
)

;; One xdata string holds 255 characters, so the payload travels in
;; pieces and is joined back before it is read.  A cut can land between
;; a backslash and what it escapes; nothing looks at a piece on its own,
;; so it does not matter.
(defun xft:chunks (s / out)
  (setq out '())
  (while (> (strlen s) 250)
    (setq out (cons (substr s 1 250) out)
          s   (substr s 251)))
  (reverse (cons s out))
)

;; The record onto one block: the marker word and the version that
;; wrote it, the scale and the WCS base point as reals, then the
;; payload.  WCS because a base kept in the UCS of the day would be
;; read back under whatever UCS the revert happens to run in.
(defun xft:stamp (en base scale payload / items)
  (regapp *xft-xdata-app*)
  (setq items (append (list (cons 1000 *xft-xdata-app*)
                            (cons 1000 *xft-version*)
                            (cons 1040 scale)
                            (cons 1040 (car base))
                            (cons 1040 (cadr base))
                            (cons 1040 (if (caddr base) (caddr base) 0.0)))
                      (mapcar '(lambda (c) (cons 1000 c))
                              (xft:chunks payload))))
  (entmod (append (entget en)
                  (list (list -3 (cons *xft-xdata-app* items)))))
)

;; ...and back: (version scale base payload), or nil when this entity
;; carries no record of ours.
(defun xft:record (en / x app strs nums p)
  (setq x (assoc -3 (entget en (list *xft-xdata-app*))))
  (if x (setq app (assoc *xft-xdata-app* (cdr x))))
  (if app
    (progn
      (setq strs '() nums '())
      (foreach p (cdr app)
        (cond ((= (car p) 1000) (setq strs (cons (cdr p) strs)))
              ((= (car p) 1040) (setq nums (cons (cdr p) nums)))))
      (setq strs (reverse strs) nums (reverse nums))
      (if (and (cdr strs) (= (car strs) *xft-xdata-app*)
               (= 4 (length nums)))
        (list (cadr strs)
              (car nums)
              (list (cadr nums) (caddr nums) (cadddr nums))
              (if (cddr strs) (apply 'strcat (cddr strs)) "")))
    )
  )
)

;; The record nearest PT gains SPEC.  A leftover text belongs to no one
;; marker, so it is kept by the point it sat closest to: revert part of
;; a survey and the annotation that came back is the annotation that
;; was next to it.
(defun xft:attach (recs pt spec / best bestd d out r)
  (if (or (null recs) (null spec) (= spec ""))
    recs
    (progn
      (foreach r recs
        (setq d (cal:d2 pt (cadr r)))
        (if (or (null best) (< d bestd)) (setq best r bestd d)))
      (setq out '())
      (foreach r recs
        (setq out (cons (if (eq r best)
                          (list (car r) (cadr r) (xft:join (caddr r) spec))
                          r)
                        out)))
      (reverse out)
    )
  )
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

(defun xft:insert (pt num / apt prev en)
  (setq apt  (list (+ (car pt) (car  *xft-att-offset*))
                   (+ (cadr pt) (cadr *xft-att-offset*))
                   (caddr pt))
        prev (entlast))
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
  ;; the block reference just made, handed back so the run can stamp
  ;; its record on it.  entlast is no way to find it: the attributes
  ;; and the SEQEND are subentities, so AutoCAD answers with the
  ;; INSERT and the VM the tests run on answers with the SEQEND.  The
  ;; walk starts from where the drawing ended before the sequence and
  ;; takes the first INSERT, which is the same entity on both.
  (setq en (if prev (entnext prev) (entnext)))
  (while (and en (/= "INSERT" (cdr (assoc 0 (entget en)))))
    (setq en (entnext en)))
  en
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
;; marker's) wins over a merely closer one.  That is what keeps a
;; tight cluster of points from stealing each other's tags.  Failing
;; that, nearest-within-reach wins, and a name is used once.
;;
;; STRIP says whether the name's letter prefix comes off ("P22" -> "22")
;; or the whole label goes in as it stands; either way MTEXT formatting
;; codes are stripped and the result is trimmed.
;;
;; Returns (made blank recs): how many blocks went in, how many of those
;; found no name and carry a blank number, and one (ename centre
;; payload) per block for the record XFTRECONV reads.  The payload is
;; taken BEFORE anything is erased, which is the only moment the marker
;; and its name text are still there to be read.
(defun xft:swap (groups names reach strip / g nm ctr best bestd bestr rank
                                            txth lim d num made blank e
                                            en spec recs)
  (setq made 0 blank 0 recs '())
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
    (setq spec "")
    (if *xft-record*
      (progn
        (foreach e (cdr g) (setq spec (xft:join spec (xft:ser e))))
        (if best (setq spec (xft:join spec (xft:ser (nth 3 best)))))))
    (setq en (xft:insert ctr num))
    (foreach e (cdr g) (entdel e))
    (if best (entdel (nth 3 best)))
    (if en (setq recs (cons (list en ctr spec) recs)))
    (setq made (1+ made))
  )
  (list made blank (reverse recs))
)


;;; -------------------------------------------------------------------
;;;  XFTCONV
;;; -------------------------------------------------------------------

(defun c:XFTCONV ( / *error* xft:restore oscm osos osclay undone guard
                     ss base wbase i en ed typ locked
                     markers names dots dotnames r recs
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
    (if lzd:report (lzd:report "XFTCONV" *xft-version* msg))
    (princ)
  )
  (if lzd:begin (lzd:begin "XFTCONV" *xft-version*))

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
  (if lzd:watch (lzd:watch ss))
  (if (not ss)
    (progn
      (princ "\nSelect the imported survey objects (Enter = everything in this space): ")
      (setq ss (ssget))
      (if lzd:watch (lzd:watch ss))))
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
          ;; getboundingbox works in WCS, SCALE wants the current UCS.
          ;; The record keeps the WCS one: a base written down in the
          ;; UCS of the day would be read back under whatever UCS the
          ;; revert runs in, and land the survey somewhere else.
          (setq wbase (xft:centre ss)
                base  (trans wbase 0 1))
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
                nblank (cadr r)
                recs   (caddr r))
          (setq r      (xft:swap dots dotnames *xft-dot-reach*
                                 *xft-dot-strip-prefix*)
                ndots  (car r)
                nmade  (+ nmade ndots)
                nblank (+ nblank (cadr r))
                recs   (append recs (caddr r)))

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
                  (progn
                    ;; read before erasing, and kept by the block it
                    ;; sat nearest: a leftover text belongs to no one
                    ;; marker, so that is the only association there is
                    (if *xft-record*
                      (setq recs (xft:attach recs (xft:txtpt ed)
                                             (xft:ser en))))
                    (entdel en)
                    (setq nleft (1+ nleft)))
                )
                (setq i (1+ i))
              )
            )
          )

          ;; ---- 6. write the record down --------------------------
          ;; Last, in one pass: the payloads are only complete once the
          ;; purge above has handed its text to the blocks it belongs
          ;; to, and stamping twice would mean reading each block's
          ;; xdata back to append to it.
          (if *xft-record*
            (foreach r recs
              (xft:stamp (car r) wbase *xft-scale* (caddr r))))

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
          (if (and *xft-record* recs)
            (princ "\nXFTRECONV puts all of it back - the blocks carry the record.")
            (princ (strcat "\n*xft-record* is off, so nothing was written down -"
                           " only U undoes this run.")))
          (princ)
        )
      )
    )
  )
  (princ)
)


;;; -------------------------------------------------------------------
;;;  XFTRECONV  -  the conversion, undone
;;; -------------------------------------------------------------------
;;;  Highlight the converted survey; every block in it that carries a
;;;  record gives back the marker and the text it replaced, the block
;;;  goes, and the whole highlight is scaled back by 1/12 about the
;;;  base point the conversion used.
;;;
;;;  ONE RUN AT A TIME.  Two conversions have two base points, and one
;;;  scale about one of them cannot undo both - so a highlight holding
;;;  blocks from two runs is refused by name rather than half-reverted.
;;;  The runs are told apart by the scale and base each block carries,
;;;  which is exactly what the difference has to be for it to matter.

;; The (ename version scale base payload) of every block in SS that
;; carries a record of ours.
(defun xft:records (ss / i en ed rec out)
  (setq i 0 out '())
  (while (< i (sslength ss))
    (setq en (ssname ss i)
          ed (entget en))
    (if (and ed (= "INSERT" (cdr (assoc 0 ed)))
             (setq rec (xft:record en)))
      (setq out (cons (cons en rec) out)))
    (setq i (1+ i))
  )
  (reverse out)
)

;; How many DIFFERENT conversions those records came from.  Two runs
;; agreeing on scale and base to the fuzz are one run as far as the
;; scale-back is concerned, which is the only thing this decides.
(defun xft:runs (recs / out r key hit k)
  (setq out '())
  (foreach r recs
    (setq key (list (nth 2 r) (nth 3 r)) hit nil)
    (foreach k out
      (if (and (not hit) (equal k key *xft-fuzz*)) (setq hit t)))
    (if (not hit) (setq out (cons key out)))
  )
  (reverse out)
)

;; The locked layers in the way: the ones the blocks to be erased sit
;; on.  A layer a rebuild writes TO is an output layer and goes through
;; ensure-layer instead, which unlocks it for good and says so.
(defun xft:locked-blocks (recs / lay out r)
  (setq out '())
  (foreach r recs
    (setq lay (cdr (assoc 8 (entget (car r)))))
    (if (and lay
             (not (member (strcase lay) (mapcar 'strcase out)))
             (xft:locked lay))
      (setq out (cons lay out)))
  )
  (reverse out)
)

(defun c:XFTRECONV ( / *error* xft:restore oscm osos osclay undone guard
                       ss recs runs locked r spec keep i en
                       scale base nback nrebuilt)

  (defun xft:restore ()
    (if oscm   (setvar "CMDECHO" oscm))
    (if osos   (setvar "OSMODE"  osos))
    (if osclay (setvar "CLAYER"  osclay))
    ;; popped on every way out, not in the handler alone -- see the
    ;; same note in c:XFTCONV
    (if *pop-error-mode* (*pop-error-mode*))
  )

  (defun *error* (msg)
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nXFTRECONV error: " msg)))
    (setq guard 0)
    (while (and (> (getvar "CMDACTIVE") 0) (< guard 10))
      (command)
      (setq guard (1+ guard)))
    (xft:restore)
    (if undone (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (princ "\nNothing was left half done - use U to roll the run back.")
    (if lzd:report (lzd:report "XFTRECONV" *xft-version* msg))
    (princ)
  )
  (if lzd:begin (lzd:begin "XFTRECONV" *xft-version*))

  (if *push-error-using-command* (*push-error-using-command*))

  (setq oscm   (getvar "CMDECHO")
        osos   (getvar "OSMODE")
        osclay (getvar "CLAYER"))

  (princ (strcat "\nXFTRECONV " *xft-version*
                 " - put a converted survey back the way it arrived."))

  ;; ---- selection, the same three ways XFTCONV takes it ------------
  (setq ss (ssget "_I"))
  (if lzd:watch (lzd:watch ss))
  (if (not ss)
    (progn
      (princ "\nSelect the converted survey (Enter = everything in this space): ")
      (setq ss (ssget))
      (if lzd:watch (lzd:watch ss))))
  (if (not ss)
    (setq ss (ssget "_X" (list (cons 410 (getvar "CTAB")))))
  )

  (cond
    ((not ss)
     (princ "\nNothing to work on.")
     (xft:restore)
     (princ))

    ;; ---- nothing here was converted, or nothing wrote it down -----
    ((not (setq recs (xft:records ss)))
     (princ "\nNo converted points here - nothing carries an XFTCONV record.")
     (princ "\n  XFTRECONV undoes an XFTCONV run, and only from the record")
     (princ "\n  XFTCONV leaves on the blocks it inserts.  A survey converted")
     (princ "\n  with *xft-record* off, or by hand, has none - U is the only")
     (princ "\n  way back from those.")
     (xft:restore)
     (princ))

    ;; ---- two runs cannot be undone by one scale -------------------
    ((> (length (setq runs (xft:runs recs))) 1)
     (princ (strcat "\nThis highlight holds points from " (itoa (length runs))
                    " different XFTCONV runs."))
     (princ "\n  Each was scaled about its own base point, and one scale back")
     (princ "\n  cannot undo two - highlight one survey at a time.")
     (xft:restore)
     (princ))

    ;; ---- a locked layer would refuse the erase --------------------
    ((setq locked (xft:locked-blocks recs))
     (princ (strcat "\nUnlock " (xft:namelist locked)
                    " first, then run XFTRECONV again."))
     (xft:restore)
     (princ))

    (t
     (setvar "CMDECHO" 0)
     (setvar "OSMODE" 0)
     (if (= 1 (logand 1 (getvar "UNDOCTL")))
       (progn
         (command "_.UNDO" "_Begin")
         (setq undone t)))

     (setq scale    (nth 2 (car recs))
           base     (nth 3 (car recs))
           nback    0
           nrebuilt 0)

     ;; ---- 1. the markers and the text, back into the drawing ----
     (setq keep (ssadd))
     (foreach r recs
       (foreach spec (xft:split (nth 4 r) ";")
         (if (/= spec "")
           (progn
             (setq en (xft:rebuild spec))
             (if en
               (progn (ssadd en keep)
                      (setq nrebuilt (1+ nrebuilt))))))
       )
       (entdel (car r))
       (setq nback (1+ nback))
     )

     ;; ---- 2. what the scale-back applies to ---------------------
     ;; everything rebuilt above, plus everything highlighted that is
     ;; still there.  Built as its own set rather than reusing the
     ;; highlight, and built AFTER the erase: a block's attributes are
     ;; erased with it, and SCALE will not take a selection carrying
     ;; entities that have gone out from under it.
     (setq i 0)
     (while (< i (sslength ss))
       (setq en (ssname ss i))
       (if (entget en) (ssadd en keep))
       (setq i (1+ i))
     )

     ;; ---- 3. and back down to the units it arrived in ------------
     (if (and (/= scale 0.0) (/= scale 1.0) (> (sslength keep) 0))
       (progn
         (princ (strcat "\nScaling " (itoa (sslength keep)) " objects back by 1/"
                        (rtos scale 2 4) " about the conversion's own base ..."))
         (command "_.SCALE" keep "" (trans base 0 1) (/ 1.0 scale))))

     (command "_.UNDO" "_End")
     (setq undone nil)
     (xft:restore)

     ;; ---- report -------------------------------------------------
     (princ (strcat "\n" (itoa nback) " \"" *xft-block*
                    "\" block(s) taken back off the survey."))
     (princ (strcat "\n" (itoa nrebuilt)
                    " marker and text object(s) put back."))
     (if (= 0 nrebuilt)
       (princ (strcat "\n  Their records carry no geometry - the run that"
                      " wrote them found markers it could not read back.")))
     (princ)
    )
  )
  (princ)
)


;;; -------------------------------------------------------------------
;;;  make sure the pieces exist as soon as the file loads
;;; -------------------------------------------------------------------

(defun c:XFTCONV-SETUP ( / *error*)
  ;; Nothing to put back -- this command opens no undo group and
  ;; changes no system variable -- but a failure still has to be SAID,
  ;; and said to LAZDIAG, or it is the one command in the build whose
  ;; bugs arrive as a bare AutoCAD message with no report behind them.
  (defun *error* (msg)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nXFTCONV-SETUP error: " msg)))
    (if lzd:report (lzd:report "XFTCONV-SETUP" *xft-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "XFTCONV-SETUP" *xft-version*))
  (cal:ensure-layer *xft-block-layer* *xft-block-layer-color*)
  (xft:ensure-block)
  (princ (strcat "\nLayer \"" *xft-block-layer* "\" and block \"" *xft-block* "\" are ready."))
  (princ)
)

(defun c:XFTCONVVER ()
  (princ (strcat "\nXFTCONV " *xft-version*))
  (princ))

(princ (strcat "\nXFTCONV.lsp " *xft-version*
               " loaded.  Type XFTCONV to scale a survey import and swap"
               " its points, XFTRECONV to put one back."))
(princ)
