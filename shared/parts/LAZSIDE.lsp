;;; ======================================================================
;;; LAZSIDE.lsp  --  fill the pool SIDE VIEW in and draw it
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  LAZSIDE     fill the side view in and run POOLSIDE
;;;            LAZSIDEVER  print the loaded version
;;;
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;
;;; THE SECTION IS THE FORM.  LAZFORM's argument, applied to the side
;;; view alone: the longitudinal section stands on the LEFT as one
;;; whole picture, and every dimension it carries has a labelled box in
;;; the column beside it with its letter as a button in front of it.
;;; The picture is read, the column is typed into, and the letter is
;;; what ties the two together.  Press Insert and POOLSIDE draws it,
;;; asking for nothing but the base point.
;;;
;;; ONE PAGE PER BOTTOM TYPE, on a tab strip: Normal, Sport, Wedge,
;;; SLope, MOdflat and SHallow are six different floors and so six
;;; different chains of letters, and picking the type on the sheet is
;;; the same answer POOLSIDE's first prompt asks for.  Nothing here is
;;; a stored picture: lzv:chart builds the section from the type's own
;;; run chain, depth stations and nominal proportions -- POOLSIDE's
;;; three tables, carried across, and tests/test_lazside.py holds them
;;; against POOLSIDE's own so they cannot drift.
;;;
;;; THE LETTERS ARE POOL'S, so a field sheet transcribes straight
;;; across:
;;;
;;;     B    overall length, wall to wall     C    wall height
;;;     D    deep end depth                   C2   depth at the break
;;;
;;;     Normal / SHallow   H  G  F  E     hopper: slope, pad, slope, flat
;;;     SLope              H  F  E        no pad -- a deep line at H
;;;     Wedge              H  F           deep line at H, floor to the wall
;;;     MOdflat            H  G  F        one pad, no shallow flat
;;;     Sport              E2 F2 G F1 E1  symmetric, a flat at each end
;;;
;;; THE THREE STATES, which are LAZFORM's and STANDARDS.md's:
;;;
;;;    box left empty   the key is not sent  -> POOLSIDE asks
;;;    NA typed in it   (key . nil) is sent  -> what NA means there
;;;    a measurement    (key . 84.0) is sent -> taken, no prompt
;;;
;;; NA in a RUN means "not measured" and is read back off B -- two of
;;; them split the remainder evenly, which is POOLSIDE's own rule and
;;; the reason a sheet with a hole in it still draws.  NA in a DEPTH is
;;; not a thing POOLSIDE has: C, D and C2 are required measurements, so
;;; an NA in one of them is demoted to an empty box and asked for.
;;;
;;; THE STATE LINE SAYS WHAT INSERT IS ABOUT TO DO, and holds the
;;; button back while it cannot do it.  Two ways a sheet is not ready:
;;; a box holding something that is neither a measurement nor NA --
;;; the chart draws the STRING, so a typo looks exactly like an answer
;;; until the line names it -- and a DEPTH PAIR POOLSIDE would refuse.
;;; D must be deeper than C and C2 must sit between them; POOLSIDE
;;; loops at the prompt until they do, and a form that can see both
;;; numbers at once should say so here instead of handing over a sheet
;;; that stops halfway through drawing.
;;;
;;; WHAT NEVER COMES OFF THE FORM: the base point.  It is picked in the
;;; drawing with the operator's own snaps live, which is the one thing
;;; a dialog cannot do for them.
;;;
;;; ZERO INSTALL, like LAZFORM, LAZSTEP and LAZPANEL: the dialog is
;;; plain DCL written to the temp folder at run time and the section is
;;; drawn with vector_image, so there is no artwork file to ship and
;;; nothing to NETLOAD.
;;;
;;; The chart is a PASSIVE image tile and must stay one.  A DCL image
;;; tile is not retained by AutoCAD: any repaint clears it to its own
;;; colour attribute and there is no expose callback to redraw from.
;;; An image_button repaints on mouse-enter and mouse-leave, so the
;;; drawing would vanish the first time the cursor crossed it.
;;; ======================================================================

(vl-load-com)

(setq *lazside-version* "v1.2")

;;; -------------------- tunables ----------------------------------------
;;;  Every knob in one place.  Each is a plain literal a person changes
;;;  by hand; the reasoning behind each sits with the code that reads
;;;  it, further down, under the same name.
;;;
;;;  Also editable, but living beside the rule that reads them:
;;;    lzv:*types*     the six bottom types and what the tabs call them
;;;    lzv:*chain*     the run chain each one is measured by
;;;    lzv:*depths*    the depth each station between the runs sits at
;;;    lzv:*nominal*   the proportions the picture is drawn at
;;;
;;;  NOT tunable here, and deliberately: the stroke font and the image
;;;  tile's colours (cal:*imgfont*, lzv:*font-*, lzv:*col-*).  The grouped
;;;  build drops those and takes CALOFIN-LIB.lsp's cal:*imgfont* and
;;;  cal:*imgcol-* instead, so a change made only here would show on
;;;  the standalone file and vanish from LAZPASS.lsp.

;;  THE FRAME THE SECTION IS DRAWN IN.  Everything is in PER-MILLE of
;;  the picture, x and y, y DOWN -- the same convention as an image
;;  tile, so the only conversion at draw time is a multiply.  Integers,
;;  so nothing depends on float formatting and two runs of the
;;  generator agree to the unit.
;;
;;  The picture reads the way the section does: the overall B along the
;;  top, the pool between the two walls under it, and the run chain on
;;  one baseline below the floor.
(setq lzv:*b-y*      120)       ; the overall B, across the top
(setq lzv:*water-y*  230)       ; the waterline: the top of both walls
(setq lzv:*sec-x0*    90)       ; the left wall...
(setq lzv:*sec-x1*   910)       ; ...and the right one
(setq lzv:*shal-y*   430)       ; the floor at depth C
(setq lzv:*brk-y*    530)       ; ...at C2, the SHallow break
(setq lzv:*deep-y*   660)       ; ...and at D, the deep end
(setq lzv:*chain-y*  810)       ; the run chain's baseline
(setq lzv:*c-x*       45)       ; where C stands, outside the left wall

;; The chart column: width in cells, and its height as a DCL aspect
;; ratio (height / width of the tile itself).  A section is a wide,
;; shallow thing and the picture follows it.
(setq lzv:*chart-w* 58)
(setq lzv:*chart-a* "0.62")

;;  How wide the hint and state lines are, in character cells.  Wider
;;  than the picture beside them, because every sentence that does not
;;  fit on one line is another row of the dialog's height; the section
;;  and its column of boxes are wider than this, so nothing here
;;  decides how wide the dialog comes out.
(setq lzv:*hint-w* 92)

;; Where the dialog remembers its position between restarts (the
;; AutoCAD profile, via setenv), and where a sheet's last accepted
;; answers are kept for Recall -- one registry value per BOTTOM TYPE,
;; because a Sport's E2/F2/F1/E1 mean nothing on a Normal's H/G/F/E.
(setq lzv:*poskey* "LazSide_Pos")
(setq lzv:*recallkey* "HKEY_CURRENT_USER\\Software\\Calofin\\LazSide")

;;; -------------------- the stroke font ---------------------------------
;;;  THIS build takes the table, its metrics, the tile palette and the
;;;  seven drawing helpers from CALOFIN-LIB.lsp -- cal:*imgfont*, the
;;;  three cal:*imgfont-* sizes, cal:*imgcol-* and cal:img* -- shared
;;;  with the other two chart forms, which carried the same copy.  The
;;;  standalone file keeps its own, because it has to load alone.
;;;  DCL has no way to draw text into an image tile -- vector_image draws
;;;  line segments and that is the whole of it -- so the letters and the
;;;  numbers on the chart are stroked out of segments.
;;;
;;;  One entry per character, in the library: the glyph as a list of
;;;  polylines, each a flat list of x y x y ... in TENTHS of a font
;;;  unit, on a cell 4 wide and 6 tall with y running DOWN the way
;;;  image-tile pixels do.



;;; -------------------- the six bottoms ----------------------------------
;;;  POOLSIDE's three tables, carried across: the run chain a bottom is
;;;  measured by, the depth each station between the runs sits at, and
;;;  the proportions of B the picture is drawn at before an answer is
;;;  in.  They are what separates one bottom from another and they are
;;;  all the picture needs.
;;;
;;;  They are a COPY, because a lisp/ file has to load alone and
;;;  POOLSIDE may not be in the session when this one is.  A copy is a
;;;  thing that drifts, so tests/test_lazside.py re-reads psd:chain,
;;;  psd:depths and psd:nominal out of POOLSIDE.lsp and holds all three
;;;  against these entry by entry -- the same bargain LAZFORM strikes
;;;  with OASIS's reference outlines.

;; The keyword POOLSIDE answers with, and what the tab calls it.  The
;; spelling is POOLSIDE's own (psd:*btypes*), capitals and all: it is
;; the answer that travels, not a label.
(setq lzv:*types*
  '(("Normal"  "Normal hopper")
    ("Sport"   "Sport")
    ("Wedge"   "Wedge")
    ("SLope"   "Slope")
    ("MOdflat" "Mod flat")
    ("SHallow" "Shallow slope")))

;; The run chain, left to right, as (letter what-it-measures).  The
;; runs always sum to B.
(setq lzv:*chain*
  '(("Normal"
     ("H" "left end to the hopper")
     ("G" "hopper pad length")
     ("F" "pad to the slope break")
     ("E" "slope break to the right end"))
    ("SHallow"
     ("H" "left end to the hopper")
     ("G" "hopper pad length")
     ("F" "pad to the slope break")
     ("E" "break to the right end"))
    ("SLope"
     ("H" "left end to the deep line")
     ("F" "deep line to the slope break")
     ("E" "slope break to the right end"))
    ("Wedge"
     ("H" "left end to the deep line")
     ("F" "deep line to the right wall"))
    ("MOdflat"
     ("H" "left end to the flat pad")
     ("G" "flat pad length")
     ("F" "pad to the right end"))
    ("Sport"
     ("E2" "left end to the slope")
     ("F2" "slope to the deep flat")
     ("G"  "deep flat length")
     ("F1" "deep flat to the slope")
     ("E1" "slope to the right end"))))

;; The depth each station sits at, one more than there are runs: "c" is
;; the wall height, "d" the deep end, "c2" the SHallow break.
(setq lzv:*depths*
  '(("Normal"  "c" "d" "d" "c" "c")
    ("SHallow" "c" "d" "d" "c2" "c")
    ("SLope"   "c" "d" "c" "c")
    ("Wedge"   "c" "d" "c")
    ("MOdflat" "c" "d" "d" "c")
    ("Sport"   "c" "c" "d" "d" "c" "c")))

;; Guide proportions of B, before a single run has been answered.  The
;; picture is drawn at these until a number replaces a letter -- it is
;; a chart and not a scale drawing, so they never move.
(setq lzv:*nominal*
  '(("Normal"  0.12 0.20 0.40 0.28)
    ("SHallow" 0.12 0.20 0.40 0.28)
    ("SLope"   0.12 0.58 0.30)
    ("Wedge"   0.12 0.88)
    ("MOdflat" 0.10 0.70 0.20)
    ("Sport"   0.12 0.20 0.30 0.26 0.12)))

(defun lzv:title (ty / p)
  (if (setq p (assoc ty lzv:*types*)) (cadr p) ty))

(defun lzv:chain (ty) (cdr (assoc ty lzv:*chain*)))

(defun lzv:depths (ty) (cdr (assoc ty lzv:*depths*)))

(defun lzv:nominal (ty) (cdr (assoc ty lzv:*nominal*)))

;; Is POOLSIDE in this session?  An unbound symbol reads as nil, so
;; this is the same test LAZFORM makes of POOL.
(defun lzv:loaded ( ) (if psd:run-with-answers T))

;; The form key a letter is stored under: "E2" -> e2, "H" -> h.  The
;; same spelling POOLSIDE's psd:key makes, which is what lets a sheet
;; be handed straight over.
(defun lzv:key (s) (strcase s t))

;;; -------------------- generating the chart -----------------------------
;;;  A chart is (style title (outline ...) (dimension ...)).
;;;
;;;  A dimension is (letter key x1 y1 x2 y2 side label), where side is
;;;  "h" or "v" -- which way the measurement runs, and so where its text
;;;  sits.  The arrow, the letter and the typed value all come off those
;;;  two endpoints, so there is no separate position table that could
;;;  fall out of step with the drawing.  It is LAZFORM's and LAZSTEP's
;;;  record, unchanged, because it is the same picture engine.

;; The per-mille y a depth code sits at.
(defun lzv:depthy (code)
  (cond ((= code "d")  lzv:*deep-y*)
        ((= code "c2") lzv:*brk-y*)
        (t             lzv:*shal-y*)))

;; The stations between the runs, left to right, as (x y): one more than
;; there are runs.  x walks the nominal proportions across the section,
;; y is whatever depth that station sits at.
(defun lzv:stations (ty / out nom deps run x i p)
  (setq nom  (lzv:nominal ty)
        deps (lzv:depths ty)
        run  (- lzv:*sec-x1* lzv:*sec-x0*)
        x    0.0
        i    0
        out  (list (list lzv:*sec-x0* (lzv:depthy (nth 0 deps)))))
  (foreach p nom
    (setq x   (+ x p)
          i   (1+ i)
          out (cons (list (+ lzv:*sec-x0* (fix (* run x)))
                          (lzv:depthy (nth i deps)))
                    out)))
  (reverse out))

;; The section itself, as one closed polyline: down the left wall,
;; along the floor station by station, up the right wall and back along
;; the waterline.
(defun lzv:outline (ty / sta out s)
  ;; out is consed newest-first and reversed once at the end, so the
  ;; seed reads BACKWARDS: y before x, or the waterline starts at
  ;; (230 . 90) instead of (90 . 230)
  (setq sta (lzv:stations ty)
        out (list lzv:*water-y* lzv:*sec-x0*))
  (foreach s sta
    (setq out (cons (cadr s) (cons (car s) out))))
  (setq out (cons lzv:*water-y* (cons lzv:*sec-x1* out)))
  (setq out (cons lzv:*water-y* (cons lzv:*sec-x0* out)))
  (list (reverse out)))

;; The deepest station, and the SHallow break: where D and C2 are
;; measured.  Read off the depth codes rather than listed, so a table
;; edit moves the dimension with the floor it measures.
(defun lzv:stationof (ty code / deps i out c)
  (setq deps (lzv:depths ty) i 0)
  (foreach c deps
    (if (and (null out) (= c code)) (setq out i))
    (setq i (1+ i)))
  out)

;; Every dimension the section carries: B across the top, the run chain
;; along its own baseline, and C, D and C2 where they fall.
(defun lzv:dims (ty / out sta i c n x)
  (setq sta (lzv:stations ty))
  ;; the overall, across the top
  (setq out (list (list "B" "b" lzv:*sec-x0* lzv:*b-y* lzv:*sec-x1* lzv:*b-y*
                        "h" "overall length, wall to wall")))
  ;; the run chain, one dimension per run, end to end on one baseline
  (setq i 0)
  (foreach c (lzv:chain ty)
    (setq out (cons (list (car c) (lzv:key (car c))
                          (car (nth i sta)) lzv:*chain-y*
                          (car (nth (1+ i) sta)) lzv:*chain-y*
                          "h" (cadr c))
                    out)
          i   (1+ i)))
  ;; C, outside the left wall: the wall height, which is the shallow
  ;; depth everywhere the floor is at "c"
  (setq out (cons (list "C" "c" lzv:*c-x* lzv:*water-y* lzv:*c-x* lzv:*shal-y*
                        "v" "wall height (shallow depth)")
                  out))
  ;; D, AT the first station the floor is deep at, not beside it: the
  ;; floor turns its corner there, so a dimension dropped on that x
  ;; lands on the point it measures.  Stand it off by a hair and it
  ;; misses -- on a Wedge and a SLope the floor is already climbing one
  ;; per-mille later, so the foot of the line would hang below it
  (setq n (lzv:stationof ty "d")
        x (car (nth n sta)))
  (setq out (cons (list "D" "d" x lzv:*water-y* x lzv:*deep-y*
                        "v" "deep end depth")
                  out))
  ;; C2, only where the style has a break to measure it at
  (if (setq n (lzv:stationof ty "c2"))
    (progn
      (setq x (car (nth n sta)))
      (setq out (cons (list "C2" "c2" x lzv:*water-y* x lzv:*brk-y*
                            "v" "depth where the shallow floor meets the break")
                      out))))
  (reverse out))

;; The chart for a bottom type.  This is the whole of the picture --
;; everything downstream reads it as data.
(defun lzv:chart (ty)
  (list ty (lzv:title ty) (lzv:outline ty) (lzv:dims ty)))

(defun lzv:c-type (c) (nth 0 c))
(defun lzv:c-title (c) (nth 1 c))
(defun lzv:c-outline (c) (nth 2 c))
(defun lzv:c-dims (c) (nth 3 c))

;; Every key the chart can answer, in drawing order.
(defun lzv:keys (c / d out)
  (foreach d (lzv:c-dims c) (setq out (cons (cadr d) out)))
  (reverse out))

;; Is this key a depth?  The three that POOLSIDE requires a measurement
;; for, which is what makes NA in one of them an empty box rather than
;; an answer.
(defun lzv:depthkey (k) (if (member k '("c" "d" "c2")) T))

;; ...and a run?  Everything that is neither a depth nor the overall,
;; which is the set NA means "read it back off B" in.
(defun lzv:runkey (k) (and (/= k "b") (not (lzv:depthkey k))))

;;; -------------------- the answers -------------------------------------
;;;  What is typed is kept as the STRING the user typed, so the chart can
;;;  show it back exactly as entered -- 2'6" stays 2'6" -- and it is only
;;;  turned into a number when POOLSIDE is handed the form.

;;;  ONE QUESTION ON THIS SHEET IS NOT A LETTER.  POOLSIDE draws the
;;;  deep end on the left, the way the letters are measured, and asks
;;;  whether to swap the section end for end -- which is a fact about
;;;  the sheet the section is going under and not a measurement, so it
;;;  is a dropdown rather than a box.  "(ask)" at the head of it is the
;;;  form's version of an empty box, and the only honest default: the
;;;  prompt has a keyboard default of its own.

(setq lzv:*asks*
  '(("mirror" "Put the deep end on the RIGHT" ("(ask)" "Yes" "No"))))

(setq lzv:*vals* nil)           ; ((key . "typed") ...)
(setq lzv:*sel* nil)            ; ((stem . index) ...) for the dropdowns
(setq lzv:*type* "Normal")      ; which bottom is being filled in
(setq lzv:*chart* nil)          ; the chart for it
(setq lzv:*focus* nil)          ; the key whose box has the caret
(setq lzv:*pos* nil)            ; where the dialog was last standing
(setq lzv:*go* nil)             ; the type a tab click asked for

(defun lzv:get (key / p)
  (if (setq p (assoc key lzv:*vals*)) (cdr p) ""))

(defun lzv:put (key v / out p)
  (foreach p lzv:*vals* (if (/= (car p) key) (setq out (cons p out))))
  (setq lzv:*vals* (reverse (cons (cons key v) out))))

;; A dropdown's selected index, 0 -- "(ask)" -- until one is picked.
(defun lzv:sel (stem / p)
  (if (setq p (assoc stem lzv:*sel*)) (cdr p) 0))

(defun lzv:sput (stem i / out p)
  (foreach p lzv:*sel* (if (/= (car p) stem) (setq out (cons p out))))
  (setq lzv:*sel* (reverse (cons (cons stem i) out))))

;; ...and the WORD it is standing on, or nil for "(ask)", which sends
;; nothing at all and leaves the prompt to ask.
(defun lzv:selword (stem / d i)
  (setq d (assoc stem lzv:*asks*) i (lzv:sel stem))
  (if (and d (> i 0)) (nth i (caddr d))))

;;; -------------------- remembering the last sheet -----------------------
;;;  A sheet you have just drawn is very often the shape of the next one:
;;;  the same pool from a different survey, or the same one corrected.
;;;  Recall puts the last accepted answers for THIS BOTTOM TYPE back
;;;  into the boxes -- and only into the EMPTY ones, so it can never
;;;  overwrite a number you have just typed, and pressing it twice does
;;;  nothing the first press did not.
;;;
;;;  It is a BUTTON and never a default.  Pre-filling a sheet on open
;;;  would put the last section's numbers on this one, and a wrong
;;;  number that looks answered is worse than an empty box: the state
;;;  line would call the sheet finished, and POOLSIDE would never ask.
;;;
;;;  The button is greyed when this bottom type has nothing stored,
;;;  which is the whole of the "nothing happened" case -- no message
;;;  needed, and the state line reports the fill by moving on its own.

;;  (lzv:*recallkey* itself is set in the TUNABLES block at the top of the file.)

;;  A sheet is stored as one string, "key=typed;key=typed".  A value
;;  carrying ";" or "=" would read back as two pairs or the wrong pair,
;;  so it is dropped rather than written -- nothing a box legitimately
;;  holds contains either, so this guards the impossible.

;; Store this chart's answers under its own value name, so one chart's
;; sheet can never come back on another's.
(defun lzv:recall-save (slot / s)
  (setq s (cal:kvpack lzv:*vals*))
  (if (/= s "")
    (vl-catch-all-apply 'vl-registry-write
                        (list lzv:*recallkey* slot s)))
  s)

(defun lzv:recall-read (slot / s)
  (setq s (vl-catch-all-apply 'vl-registry-read
                              (list lzv:*recallkey* slot)))
  (if (and (not (vl-catch-all-error-p s)) (= (type s) 'STR))
    (cal:kvunpack s)))

;;; -------------------- what the sheet still owes ------------------------
;;;  LAZFORM's state line.  Nothing here changes what is SENT --
;;;  lzv:form is still the only thing that decides that.  It reports
;;;  what lzv:form is about to do, and holds Insert back when that
;;;  would not be a run.

;; Every box on this sheet.  There is no greying here: a bottom type is
;; a page of its own, so a letter that does not apply is not on it.
(defun lzv:livekeys ( ) (lzv:keys lzv:*chart*))

;; A box holding something that is neither a measurement nor NA.  The
;; chart draws the STRING, so a typo looks exactly like an answer until
;; its letter is named here.
(defun lzv:unreadable ( / out k v)
  (foreach k (lzv:livekeys)
    (setq v (cal:trim (lzv:get k)))
    (if (and (/= v "")
             (or (eq (cal:formanswer v) 'SKIP)
                 ;; POOLSIDE has no NA for a depth: C, D and C2 are
                 ;; required measurements, so NA in one is not an
                 ;; answer it could take
                 (and (lzv:depthkey k) (null (cal:formanswer v)))))
      (setq out (cons k out))))
  (reverse out))

(defun lzv:togo ( / out k)
  (foreach k (lzv:livekeys)
    (if (= (cal:trim (lzv:get k)) "") (setq out (cons k out))))
  (reverse out))

;; A box is named by the LETTER the drawing shows, not by its key: a
;; key would send the drafter hunting for something the picture does
;; not print.
(defun lzv:tagof (key / d out)
  (foreach d (lzv:c-dims lzv:*chart*)
    (if (and (not out) (= (cadr d) key)) (setq out (car d))))
  (if out out (strcase key)))

(defun lzv:taglist (keys / n i named k)
  (setq n (length keys) i 0)
  (foreach k keys
    (if (< i 3) (setq named (cons (lzv:tagof k) named) i (1+ i))))
  (setq named (reverse named))
  (if (> n 3)
    (strcat (cal:andjoin named nil) " and " (itoa (- n 3)) " more")
    (cal:andjoin named t)))

;; The number in a box ON THE SHEET IN FRONT OF YOU, or nil when there
;; is not one there.  The live test is the point of it: lzv:*vals* is
;; keyed across the whole run, so a letter THIS bottom does not carry
;; is still in there holding what the last tab typed against it.
;; lzv:form sends the live keys and nothing else, so such a value
;; cannot reach POOLSIDE -- and a check that read it anyway would judge
;; the sheet by a box the page does not show.
(defun lzv:num (key / v)
  (if (member key (lzv:livekeys))
    (progn
      (setq v (cal:formanswer (cal:trim (lzv:get key))))
      (if (numberp v) v))))

;;  THE DEPTH PAIR POOLSIDE WOULD REFUSE.  A deep end that is not deeper
;;  than the wall is not a deep end, and the SHallow break sits between
;;  them.  POOLSIDE loops at the prompt until they do -- which is the
;;  right thing at a prompt and the wrong thing to hand a sheet to: the
;;  run would draw half a section and then stop to argue.  A form can
;;  see both numbers at once, so it says so here instead.
;;
;;  C2 is read through the same live test as the other two and that is
;;  not belt and braces: only SHallow has a break to measure, so a C2
;;  typed on that tab and left behind would otherwise still be weighed
;;  on a Normal -- greying Insert over a letter with no box on the page
;;  and no message the drafter could act on without tabbing back.
(defun lzv:depthbad ( / cv dv c2v)
  (setq cv (lzv:num "c") dv (lzv:num "d") c2v (lzv:num "c2"))
  (cond
    ((and cv dv (<= dv cv))
     "D must be deeper than C - the deep end is not deeper than the wall.")
    ((and cv c2v dv (or (< c2v cv) (> c2v dv)))
     "C2 must be between C and D - the break cannot sit outside them.")))

;; Why this box is not an answer, as the rest of the sentence its
;; letter starts.  Three cases and they want three different things
;; said: NA in a depth is the sharp one, because NA is a word the form
;; itself tells you to type -- just not there.
(defun lzv:whybad (k / v)
  (setq v (cal:formanswer (cal:trim (lzv:get k))))
  (cond
    ((and (lzv:depthkey k) (null v))
     " is NA, and a depth has no NA - type a number, or clear it.")
    ((lzv:depthkey k)
     " is not a measurement - a depth takes a number or an empty box.")
    (t " is not a measurement - type a number, or NA, or clear it.")))

(defun lzv:state ( / bad togo n)
  (setq bad  (lzv:unreadable)
        togo (lzv:togo)
        n    (length (lzv:livekeys)))
  (cond
    ((cdr bad)
     (strcat (lzv:taglist bad)
             " are not measurements - type a number, or NA, or clear them."))
    (bad (strcat (lzv:taglist bad) (lzv:whybad (car bad))))
    ((lzv:depthbad))
    ((not togo)
     (strcat "All " (cal:plural n "box" "boxes")
             " filled - POOLSIDE will ask only for the base point."))
    ((= (length togo) n)
     (strcat "Nothing filled yet - POOLSIDE will ask for all "
             (cal:plural n "box" "boxes") ", plus the base point."))
    (t
     (strcat (itoa (- n (length togo))) " of "
             (cal:plural n "box" "boxes") " filled - POOLSIDE will ask for "
             (lzv:taglist togo) ", plus the base point."))))

;; The line, and the button it holds back.  Two reasons Insert cannot
;; go: a box that would be dropped, and a depth pair POOLSIDE would
;; refuse.  Both are on the line that greys it, so the button is never
;; grey for a reason the page does not give.
(defun lzv:restate ( / )
  (set_tile "state" (lzv:state))
  (mode_tile "accept" (if (or (lzv:unreadable) (lzv:depthbad)) 1 0))
  (princ))

;; The slot a sheet's answers are stored under.  A bottom type is a
;; different chain of letters, so a Sport's sheet must never come back
;; on a Normal one.
(defun lzv:recall-slot ( ) lzv:*type*)

;; Fill the EMPTY boxes from the stored sheet, and repaint.  Only the
;; empty ones: a recall must never overwrite a number just typed, and
;; pressing it twice must do nothing the first press did not.
(defun lzv:recall ( / had n k v)
  (setq had (lzv:recall-read (lzv:recall-slot)) n 0)
  (foreach k (lzv:livekeys)
    (if (and (= (cal:trim (lzv:get k)) "")
             (setq v (cdr (assoc k had))))
      (progn (lzv:put k v) (set_tile k v) (setq n (1+ n)))))
  (lzv:redraw)
  (lzv:restate)
  n)

;;; -------------------- what POOLSIDE is handed --------------------------
;;;
;;;  THE BOTTOM TYPE GOES FIRST, and it is the page itself: whichever
;;;  tab is open is the answer POOLSIDE's first prompt gets, so a sheet
;;;  can never be filled in for one floor and drawn as another.
;;;
;;;  Then the letters, in the order the drawing carries them.  Every
;;;  key is POOLSIDE's own, spelled by lzv:key exactly as psd:key
;;;  spells it, so the alist is handed straight over.

(defun lzv:form ( / out k a d v)
  (setq out (list (cons 'style lzv:*type*)))
  ;; the dropdowns first: a word on the wire, or nothing when the
  ;; sheet was left saying "(ask)"
  (foreach d lzv:*asks*
    (if (setq v (lzv:selword (car d)))
      (setq out (cons (cons (read (car d)) v) out))))
  (foreach k (lzv:livekeys)
    (setq a (cal:formanswer (cal:trim (lzv:get k))))
    ;; a depth has no NA at the prompt, so an NA in one counts as an
    ;; empty box: sending nil would be sending an answer POOLSIDE
    ;; cannot use, and the run would stop to ask anyway
    (if (and (null a) (lzv:depthkey k)) (setq a 'SKIP))
    (if (not (eq a 'SKIP))
      (setq out (cons (cons (read k) a) out))))
  (reverse out))

;;; -------------------- drawing the chart -------------------------------
;;;  Pixel coordinates, origin top-left, y down -- image-tile convention,
;;;  which is why the per-mille data is generated that way too and needs
;;;  no flipping here.  dimx_tile / dimy_tile report the LARGEST legal
;;;  coordinate, not the size, and are only answerable while the dialog
;;;  is up, so everything below runs between new_dialog and start_dialog.

(setq lzv:*dx* 0)               ; the tile's extent this time round
(setq lzv:*dy* 0)

                                ; picked for the dialog, which is what
                                ; -16 and -15 above already follow --
                                ; a plain 8 is swallowed by a dark one
                                ; The one colour here that reads either
                                ; way round, so it stays a number
                                ; is blue on a light dialog and a
                                ; brighter cyan on a dark one, where
                                ; blue 5 is very nearly the background

;; per-mille -> pixels
(defun lzv:px (v) (fix (/ (* v lzv:*dx*) 1000.0)))
(defun lzv:py (v) (fix (/ (* v lzv:*dy*) 1000.0)))

;;  An outline element is either a POLYLINE -- a flat list of per-mille
;;  numbers, x y x y ... -- or an ARC, written
;;
;;      ("A" cx cy rx ry from to)
;;
;;  with the centre and both radii in per-mille and the angles in
;;  degrees.  A section is all straight lines, so nothing here draws an
;;  arc today; the two helpers are the library's and are carried so the
;;  picture engine is the same one the other three forms use.

;; A polyline given as a flat per-mille list, in pixels.
(defun lzv:pline (flat col / a b)
  (while (and flat (cddr flat))
    (setq a (list (lzv:px (car flat)) (lzv:py (cadr flat)))
          b (list (lzv:px (caddr flat)) (lzv:py (cadddr flat))))
    (vector_image (car a) (cadr a) (car b) (cadr b) col)
    (setq flat (cddr flat))))

;; The dimension line, in per-mille, with an arrowhead at each end.
;; The head shapes are the whole of it because a section has no
;; diagonal dimension: every letter on it runs either along the pool or
;; down into it.
(defun lzv:arrow (x1 y1 x2 y2 col / a b p q)
  (vector_image (lzv:px x1) (lzv:py y1) (lzv:px x2) (lzv:py y2) col)
  (setq a 6 b 3)
  (if (= y1 y2)
    (progn                              ; horizontal: heads point in
      (setq p (list (lzv:px (min x1 x2)) (lzv:py y1))
            q (list (lzv:px (max x1 x2)) (lzv:py y1)))
      (vector_image (car p) (cadr p) (+ (car p) a) (- (cadr p) b) col)
      (vector_image (car p) (cadr p) (+ (car p) a) (+ (cadr p) b) col)
      (vector_image (car q) (cadr q) (- (car q) a) (- (cadr q) b) col)
      (vector_image (car q) (cadr q) (- (car q) a) (+ (cadr q) b) col))
    (progn                              ; vertical
      (setq p (list (lzv:px x1) (lzv:py (min y1 y2)))
            q (list (lzv:px x1) (lzv:py (max y1 y2))))
      (vector_image (car p) (cadr p) (- (car p) b) (+ (cadr p) a) col)
      (vector_image (car p) (cadr p) (+ (car p) b) (+ (cadr p) a) col)
      (vector_image (car q) (cadr q) (- (car q) b) (- (cadr q) a) col)
      (vector_image (car q) (cadr q) (+ (car q) b) (- (cadr q) a) col))))

;; Where one dimension's text belongs, and what it says: the LETTER
;; until a value is typed, then the value in the letter's place.  A
;; value too wide for its own span is shrunk to fit rather than allowed
;; to run into its neighbours -- H, G, F and E sit shoulder to shoulder
;; along the chain and every one of them can carry a feet-and-inches
;; number.
(defun lzv:label (d / letter key x1 y1 x2 y2 side txt sc w h lx ly span mx my)
  (setq letter (car d) key (cadr d)
        x1 (lzv:px (nth 2 d)) y1 (lzv:py (nth 3 d))
        x2 (lzv:px (nth 4 d)) y2 (lzv:py (nth 5 d))
        side (nth 6 d)
        txt (lzv:get key)
        mx (/ (+ x1 x2) 2) my (/ (+ y1 y2) 2))
  (if (= txt "")
      (setq txt letter sc (lzv:basesc))
      (setq sc (/ (* (lzv:basesc) 90) 100)))
  (setq w (cal:imgtextw txt sc))
  (if (and (= side "h") (> w 0))
      (progn
        (setq span (abs (- x2 x1)))
        (if (> w span)
            (progn
              (setq sc (/ (* sc span) w))
              (if (< sc (/ (* (lzv:basesc) 55) 100))
                  (setq sc (/ (* (lzv:basesc) 55) 100)))
              (setq w (cal:imgtextw txt sc))))))
  (setq h (cal:imgtexth sc))
  (if (= side "h")
      (setq lx (- mx (/ w 2)) ly (- y1 h 4))
      ;; a vertical dimension labels at the TOP of its span, centred on
      ;; its own line, EXCEPT when that would run off the left edge --
      ;; C stands outside the left wall with no room on its outside
      (progn
        (setq ly (+ (min y1 y2) 5))
        (setq lx (if (< (- mx (/ w 2)) 2) (+ mx 4) (- mx (/ w 2))))))
  ;; and nothing is allowed off the edge of the picture
  (if (< lx 2) (setq lx 2))
  (if (> (+ lx w) (- lzv:*dx* 2)) (setq lx (- lzv:*dx* w 2)))
  (if (< ly 2) (setq ly 2))
  (if (> (+ ly h) (- lzv:*dy* 2)) (setq ly (- lzv:*dy* h 2)))
  ;; blank the strip behind it so the dimension line does not run
  ;; through the characters
  (fill_image (- lx 3) (- ly 2) (+ w 6) (+ h 4) cal:*imgcol-back*)
  (if (= key lzv:*focus*)
      (cal:imgpline (list (- lx 3) (- ly 2) (+ lx w 3) (- ly 2)
                         (+ lx w 3) (+ ly h 2) (- lx 3) (+ ly h 2)
                         (- lx 3) (- ly 2))
                   (cal:ink cal:*imgcol-hi* 'hi)))
  (cal:imgtext txt lx ly sc
            (if (= (lzv:get key) "") cal:*imgcol-line* cal:*imgcol-val*)))

;; The whole picture, start to end.  Every vector goes between one
;; start_image and one end_image so the tile is painted once: the
;; outline first, then every dimension's line, then every dimension's
;; text over the top of it -- the text blanks the strip behind itself,
;; so a letter never has a dimension line running through it.
(defun lzv:redraw ( / c poly d col)
  (setq c        lzv:*chart*
        lzv:*dx* (dimx_tile "chart")
        lzv:*dy* (dimy_tile "chart")
        ;; resolved once, before the loop: the measurement behind 'auto
        ;; is a COM round trip, and there is one dimension per letter
        col      (cal:ink cal:*imgcol-dim* 'dim))
  (start_image "chart")
  (fill_image 0 0 lzv:*dx* lzv:*dy* cal:*imgcol-back*)
  (foreach poly (lzv:c-outline c)
    (lzv:pline (cal:imgflatten poly) cal:*imgcol-line*))
  (foreach d (lzv:c-dims c)
    (lzv:arrow (nth 2 d) (nth 3 d) (nth 4 d) (nth 5 d) col))
  (foreach d (lzv:c-dims c) (lzv:label d))
  (end_image)
  (princ))

;; The size to letter the chart at.  Derived from the tile rather than
;; fixed: an image tile's pixel size falls out of the user's dialog font
;; and display DPI, and is not knowable until the dialog is up.
(defun lzv:basesc ( / sc)
  (setq sc (/ (* lzv:*dy* 100) 1560))
  (if (< sc 12) 12 sc))

;;; -------------------- the generated DCL --------------------------------
;;  Two columns: the section on the left as a passive image, the boxes
;;  on the right in the picture's own order, each labelled with its
;;  letter so the list and the picture read as one thing.

;; The DCL name of a bottom type's page.
(defun lzv:dlgname (ty) (strcat "lazside_" (strcase ty t)))

;; The tab strip: one button per bottom type, the current one disabled
;; so it reads as the page you are on rather than as somewhere to go.
(defun lzv:tabstrip (cur / out d)
  (setq out (list "  : row {"))
  (foreach d lzv:*types*
    (setq out (append out
                (list (strcat "    : button { key = \"tab_" (car d)
                              "\"; label = \"" (cadr d) "\";"
                              (if (= (car d) cur) " is_enabled = false;" "")
                              " }")))))
  (append out (list "  }")))

;; One column row: the letter as a button, then the box.  Clicking the
;; letter puts the caret in that box and rings the dimension on the
;; chart -- which is as close to clicking the drawing itself as DCL
;; allows, and the button sits against the box it fills.
(defun lzv:colcell (d / out)
  (list "        : row {"
        (strcat "          : button { key = \"pick_" (cadr d)
                "\"; label = \"" (car d) "\"; fixed_width = true; }")
        (strcat "          : edit_box { key = \"" (cadr d)
                "\"; edit_width = 9; label = \"" (nth 7 d) "\"; }")
        "        }"))

;; ONE PAGE: the section, and every letter it carries with a box.
(defun lzv:dcl-one (c / out ty d l)
  ;; out is consed newest-first and reversed once at the end, so this
  ;; seed list reads BACKWARDS: the label second here puts it second in
  ;; the file, after the line that opens the dialog.  The other way
  ;; round emits an attribute before its own dialog, which is not DCL.
  (setq ty  (lzv:c-type c)
        out (list (strcat "  label = \"LazSide - " (lzv:c-title c) "\";")
                  (strcat (lzv:dlgname ty) " : dialog {")))
  (foreach l (lzv:tabstrip ty) (setq out (cons l out)))
  (setq out (cons "  : row {" out))
  ;; A PASSIVE image tile, deliberately -- see the header for what an
  ;; image_button costs -- and ONE of them: the whole section, whole.
  (setq out (cons (strcat "    : image { key = \"chart\"; width = "
                          (itoa lzv:*chart-w*) "; aspect_ratio = "
                          lzv:*chart-a* "; fixed_width = true; "
                          "fixed_height = true; color = -15; }")
                  out))
  (setq out (cons "    : column {" out))
  (setq out (cons "      : boxed_column {" out))
  (setq out (cons "        label = \"Overall\";" out))
  (foreach d (lzv:c-dims c)
    (if (= (cadr d) "b")
      (foreach l (lzv:colcell d) (setq out (cons l out)))))
  (setq out (cons "      }" out))
  (setq out (cons "      : boxed_column {" out))
  (setq out (cons "        label = \"Floor runs, left to right\";" out))
  (foreach d (lzv:c-dims c)
    (if (lzv:runkey (cadr d))
      (foreach l (lzv:colcell d) (setq out (cons l out)))))
  (setq out (cons "      }" out))
  (setq out (cons "      : boxed_column {" out))
  (setq out (cons "        label = \"Depths\";" out))
  (foreach d (lzv:c-dims c)
    (if (lzv:depthkey (cadr d))
      (foreach l (lzv:colcell d) (setq out (cons l out)))))
  (setq out (cons "      }" out))
  (setq out (cons "      : boxed_column {" out))
  (setq out (cons "        label = \"The rest of the run\";" out))
  (foreach d lzv:*asks*
    (setq out (cons (strcat "        : popup_list { key = \"" (car d)
                            "\"; label = \"" (cadr d)
                            "\"; edit_width = 8; }")
                    out)))
  (setq out (cons "      }" out))
  (setq out (cons "    }" out))
  (setq out (cons "  }" out))
  (setq out (cons "  spacer;" out))
  (foreach l (list (strcat "Read the letters off the section and type the"
                           " numbers in the column beside it.")
                   (strcat "NA in a RUN means not measured: it is read back"
                           " off B, and two of them split what is left.")
                   (strcat "A depth has no NA - C, D and C2 are measured or"
                           " they are asked for at the prompt.")
                   (strcat "A box takes 24, or a feet-and-inches spelling -"
                           " both read.  The base point stays a pick."))
    (setq out (cons (strcat "  : text { width = " (itoa lzv:*hint-w*)
                            "; label = \"" l "\"; }")
                    out)))
  ;; The state line.  It carries no label here: it is written before
  ;; the dialog is shown and rewritten on every change, so a label in
  ;; the file would only be the wrong answer for an instant.
  (setq out (cons (strcat "  : text { key = \"state\"; width = "
                          (itoa lzv:*hint-w*) "; }") out))
  (setq out (cons "  : row {" out))
  (setq out (cons (strcat "    : button { key = \"recall\"; "
                          "label = \"Recall last\"; fixed_width = true; }")
                  out))
  (setq out (cons (strcat "    : button { key = \"accept\"; label = \"Insert\";"
                          " is_default = true; fixed_width = true; }")
                  out))
  (setq out (cons (strcat "    : button { key = \"cancel\"; label = \"Cancel\";"
                          " is_cancel = true; fixed_width = true; }")
                  out))
  (setq out (cons "  }" out))
  (reverse (cons "}" out)))

;; Every bottom type's page, in one file -- so a tab click needs
;; nothing from disk that opening the form did not already write.
(defun lzv:dcl-lines ( / out d)
  (foreach d lzv:*types*
    (setq out (append out (lzv:dcl-one (lzv:chart (car d))) (list ""))))
  out)

(defun lzv:write-lines (fh / l)
  (foreach l (lzv:dcl-lines) (write-line l fh)))

(defun lzv:write-dcl ( / f fh err)
  (setq f (vl-filename-mktemp "lazside" nil ".dcl"))
  (if (and f (setq fh (open f "w")))
    (progn
      (setq err (vl-catch-all-apply 'lzv:write-lines (list fh)))
      (close fh)
      (cond
        ((vl-catch-all-error-p err) (vl-file-delete f) nil)
        (t f)))))

;; WHERE THE DIALOG COMES BACK UP.  done_dialog reports the position it
;; closed at, and that is the only chance to find out -- DCL cannot ask
;; an open dialog where it is.  Held in lzv:*pos* alone that answer lasts
;; until the file is reloaded, so the point also goes into the AutoCAD
;; profile as "x,y" and is read back at the next open: come back after a
;; restart and the dialog is still where it was left.
(defun lzv:pos-save (p)                 ; answers with what it was given,
  (if (and p (listp p) (= (length p) 2) ; so it can wrap a done_dialog
           (numberp (car p)) (numberp (cadr p)))
    (setenv lzv:*poskey*
            (strcat (itoa (fix (car p))) "," (itoa (fix (cadr p))))))
  p)

;; The saved point, or nil when there is nothing worth trusting.  Only a
;; string this build could have written is taken -- the parse has to
;; round-trip -- so a hand-edited or foreign profile value can do no
;; more than centre the dialog, which is what it did before.  The clamp
;; is a rescue and not a fence: a point saved on a second monitor that
;; has since been unplugged would otherwise put the dialog where the
;; mouse cannot reach it.  SCREENSIZE is the drawing area rather than
;; the desktop, so the clamp can only ever pull one IN.
(defun lzv:pos-read ( / s i x y scr)
  (setq s (getenv lzv:*poskey*))
  (if (and s (setq i (vl-string-search "," s)) (> i 0))
    (progn
      (setq x (atoi (substr s 1 i))
            y (atoi (substr s (+ i 2))))
      (if (= s (strcat (itoa x) "," (itoa y)))
        (progn
          (setq scr (getvar "SCREENSIZE"))
          (if (and scr (listp scr) (= (length scr) 2)
                   (numberp (car scr)) (numberp (cadr scr)))
            (setq x (max 0 (min x (fix (- (car scr) 100.0))))
                  y (max 0 (min y (fix (- (cadr scr) 100.0))))))
          (list x y))))))

;; Open a page where the user last had the dialog.  new_dialog takes a
;; position back, but only in its four-argument form -- and a build
;; answering done_dialog with something other than a point would poison
;; every reopen, so the shape is checked before it is trusted and the
;; plain two-argument call is the fallback.  lzv:*pos* is this session's
;; answer; the profile is the one the last session left behind.
(defun lzv:newdlg (name dcl / p)
  (setq p (if lzv:*pos* lzv:*pos* (lzv:pos-read)))
  (if (and p (listp p) (= (length p) 2)
           (numberp (car p)) (numberp (cadr p)))
      (new_dialog name dcl "" p)
      (new_dialog name dcl)))

;; start_dialog, then keep where the dialog was left.  Saving here
;; rather than in the six action tiles keeps setenv out of a dialog
;; callback and gives the profile write one place to go wrong.
(defun lzv:rundlg ( / rc)
  (setq rc (start_dialog))
  (lzv:pos-save lzv:*pos*)
  rc)

;;; -------------------- the page ----------------------------------------

(defun lzv:page (dcl / d k)
  (cond
    ((not (lzv:newdlg (lzv:dlgname lzv:*type*) dcl)) 9)
    (t
     ;; the tabs -- each closes this page and names the next
     (foreach d lzv:*types*
       (action_tile (strcat "tab_" (car d))
         (strcat "(setq lzv:*go* \"" (car d) "\" lzv:*pos* (done_dialog 4))")))
     ;; the dropdowns.  A pick changes nothing that is greyed and
     ;; nothing on the picture, so it only has to restate
     (foreach d lzv:*asks*
       (start_list (car d))
       (foreach k (caddr d) (add_list k))
       (end_list)
       (set_tile (car d) (itoa (lzv:sel (car d))))
       (action_tile (car d)
         (strcat "(lzv:sput \"" (car d) "\" (atoi $value)) (lzv:restate)")))
     ;; put back what was typed the last time this sheet was on screen
     (foreach d (lzv:keys lzv:*chart*)
       (set_tile d (lzv:get d))
       (action_tile d
         (strcat "(lzv:put \"" d "\" $value) (setq lzv:*focus* \"" d "\")"
                 " (lzv:redraw) (lzv:restate)")))
     (foreach d (lzv:c-dims lzv:*chart*)
       (action_tile (strcat "pick_" (cadr d))
         (strcat "(setq lzv:*focus* \"" (cadr d) "\") (lzv:redraw)"
                 " (mode_tile \"" (cadr d) "\" 2)"
                 " (mode_tile \"" (cadr d) "\" 3)")))
     ;; the chart takes no action at all -- it is a passive image tile.
     ;; Recall does NOT close the page: it fills the empty boxes where
     ;; you are standing, and the state line moves to say so
     (action_tile "recall" "(lzv:recall)")
     (if (not (lzv:recall-read (lzv:recall-slot))) (mode_tile "recall" 1))
     (action_tile "accept" "(setq lzv:*pos* (done_dialog 1))")
     (action_tile "cancel" "(setq lzv:*pos* (done_dialog 0))")
     (lzv:redraw)
     (lzv:restate)
     (lzv:rundlg))))

;;; -------------------- the run -----------------------------------------
;;  A helper rather than the command body, so its localized *error* is
;;  out of scope by the time POOLSIDE is started: it installs its own,
;;  and a POOLSIDE that fails must report as POOLSIDE.

(defun lzv:show ( / *error* f dcl rc done out)
  (defun *error* (msg)
    (term_dialog)
    (if (and dcl (>= dcl 0)) (unload_dialog dcl))
    (setq dcl nil)
    (if f (vl-file-delete f))
    (setq f nil)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nLAZSIDE error: " msg)))
    (if lzd:report (lzd:report "LAZSIDE" *lazside-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "LAZSIDE" *lazside-version*))
  (setq lzv:*vals*  nil
        lzv:*sel*   nil
        lzv:*chart* nil
        lzv:*focus* nil
        lzv:*pos*   nil)                ; the profile decides where this
                                        ; run opens, not the last page
  ;; THE PAGE LOOP.  DCL has no tab tile and no way to rebuild a dialog
  ;; that is already up, so a change of bottom type closes this page
  ;; and opens the next -- and because done_dialog hands back where the
  ;; dialog was standing, it reopens exactly there instead of wandering
  ;; off to the middle of the screen.  Everything typed lives in
  ;; lzv:*vals*, keyed, so a letter both floors carry still holds what
  ;; was typed against it when the tab comes back.
  (while (not done)
    (setq lzv:*chart* (lzv:chart lzv:*type*)
          f           (lzv:write-dcl))
    (cond
      ((null f)
       (princ "\nLAZSIDE error: could not write the dialog file.")
       (setq done T))
      ((< (setq dcl (load_dialog f)) 0)
       (princ "\nLAZSIDE error: could not load the dialog file.")
       (vl-file-delete f)
       (setq f nil done T))
      (t
       (setq rc (lzv:page dcl))
       (unload_dialog dcl)
       (setq dcl nil)
       (vl-file-delete f)
       (setq f nil)
       (cond
         ((= rc 9)
          (princ "\nLAZSIDE error: could not open the form.")
          (setq done T))
         ((= rc 0) (setq done T))
         ((= rc 4) (setq lzv:*type* lzv:*go* lzv:*focus* nil))
         ((= rc 1)
          ;; an accepted sheet is what gets remembered -- a cancelled
          ;; one was not a section anybody used
          (lzv:recall-save (lzv:recall-slot))
          (setq out (lzv:form) done T))
         (t (setq done T))))))
  ;; the dialog's run ends with the dialog.  What the command does with
  ;; the answer -- runs POOL off the form, launches the tool picked -- is
  ;; a run of its own: left standing, this one was JOINED by it (the
  ;; command is still what CMDNAMES names), and a failure in the tool
  ;; was filed under a dialog no report can replay
  (if lzd:end (lzd:end "LAZSIDE"))
  out)

;;; -------------------- commands ----------------------------------------

;; The form, then POOLSIDE with what it collected.  POOLSIDE has to be
;; here to receive it, so say so plainly rather than opening a form
;; whose Insert button could only fail.
(defun c:LAZSIDE ( / form)
  (cond
    ((not (lzv:loaded))
     (princ "\nLAZSIDE: POOLSIDE is not loaded in this session -- APPLOAD")
     (princ "\n         lisp/poolside/POOLSIDE.lsp, or LAZPASS.lsp, which")
     (princ "\n         carries it."))
    (t
     (setq form (lzv:show))
     (cond
       ((null form) (princ "\nLAZSIDE: cancelled, nothing drawn."))
       (t
        (princ (strcat "\nLAZSIDE: " (itoa (length form))
                       " answers to POOLSIDE for a " lzv:*type*
                       " bottom; it will ask for whatever is left."))
        (psd:run-with-answers form)))))
  (princ))

(defun c:LAZSIDEVER ()
  (princ (strcat "\nLAZSIDE " *lazside-version* " (LAZSIDE.lsp) - "
                 (itoa (length lzv:*types*)) " bottom type(s)."))
  (princ))

;; Quiet inside the whole build: LAZPASS.lsp and
;; CALOFIN-LOADER.lsp set the flag while they load their members,
;; because one file's greeting is a greeting and sixty-three of
;; them is a wall the drafter scrolls past in every drawing they
;; open.  APPLOADed alone the flag is nil and this prints, which
;; is the one time somebody wants to be told.  CALVER reports the
;; whole roster whenever it is asked.
(if (not *calofin-quiet*)
  (princ (strcat "\nLAZSIDE " *lazside-version*
                 " loaded.  Type LAZSIDE to fill a side view in.")))
(princ)
