;;; ======================================================================
;;; SMARTFILLET.lsp  --  show what every rounded corner would look like,
;;;                      then cut the one that is clicked
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  SMARTFILLET     preview the radii that fit a corner, cut
;;;                            the one that is clicked, dimension it, and
;;;                            offer the rest of the corners at that size
;;;            SMARTFILLETVER  print the loaded version
;;;
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;
;;;  FILLET wants the radius BEFORE it shows anything, so the answer is
;;;  guessed, looked at, undone, and guessed again.  This turns that
;;;  round.  Pick the two lines and every radius that actually fits the
;;;  corner is drawn at once, in 6-inch steps; click the one that looks
;;;  right and that is the corner you get.
;;;
;;;    1. Select the two lines that make the corner.  Click each one on
;;;       the side you want KEPT -- exactly how FILLET reads a pick:
;;;       what lies beyond the corner is trimmed away.
;;;    2. Every radius from 6 up, in 6s, that leaves both legs something
;;;       to stand on is drawn as an arc labelled R6, R12, R18 ... plus
;;;       the two odd sizes in sf:*extras* (3 and 9), which come up but
;;;       are not the usual step and so are drawn DASHED where the 6s
;;;       are solid.  (At most sf:*maxshown* previews; when more fit,
;;;       the routine says how many it left out rather than silently
;;;       stopping.)
;;;    3. Click the one you want -- the ARC, or the R6 lettered beside
;;;       it.  Both are that size: an arc is a hairline and the label
;;;       is much the bigger target of the two, so a click that lands
;;;       on the letters is an answer rather than a fan thrown away.
;;;       The previews go, the corner is filleted for real at that
;;;       radius, and the arc gets its radius dimension -- the number
;;;       the shop needs, not just the shape.
;;;    4. It then offers the SAME radius for the rest of the corners:
;;;       two lines per corner until Done.  As soon as one repeat is
;;;       cut, the single dimension becomes "R12 Typ.", which is how the
;;;       radius would be lettered by hand.
;;;
;;;  Telling one preview from the next is the whole job of the drawing,
;;;  so three things do it at once: the fan runs light green to dark
;;;  green with the radius, every arc is part transparent so the ones
;;;  underneath still read, and each label is drawn in ITS OWN arc's
;;;  shade.  The labels climb a rung further off the leg with each
;;;  preview, because consecutive tangent points sit one step apart
;;;  along a leg and that is not room for two labels side by side.
;;;
;;;  Two lines that stop short of where they MEET are the case the fan
;;;  cannot speak for itself.  FILLET extends them to the corner, so
;;;  every arc is drawn round a point that is on neither line -- and
;;;  when the lines are yards from it, what lands on screen is a fan of
;;;  green arcs floating in space with nothing to say which two lines
;;;  they belong to.  So each leg that falls short gets a DASHED run
;;;  from its own end out to that corner: the line FILLET is going to
;;;  make, drawn before it exists.  It is a preview like the arcs --
;;;  same layer, erased with them, never left behind -- and a leg that
;;;  misses by less than sf:*gapmin* gets none, because a run shorter
;;;  than one dash is a tick on the end of a line and reads as work.
;;;
;;;  HONEFILLET is the spinoff for the sizes BETWEEN these: same corner,
;;;  same picks, but it asks for two neighbouring previews and redraws
;;;  the range between them in half-inch steps.
;;;
;;;  The whole run is one undo group: a single U puts every corner back
;;;  and takes the dimension away.
;;;
;;;  Usage
;;;    Command: SMARTFILLET
;;;    Command: SMARTFILLETVER   prints the version
;;;
;;;  Tunables (setq them after loading if a drawing needs different
;;;  sizes or names, e.g. in a startup file):
;;;    sf:*first*      smallest radius previewed          (6.0)
;;;    sf:*step*       step between previews              (6.0)
;;;    sf:*extras*     odd radii offered too, drawn dashed (3 and 9)
;;;    sf:*maxshown*   most previews drawn at once        (10)
;;;    sf:*fit*        fraction of a leg a fillet may eat (0.98)
;;;    sf:*layer*      layer the previews are drawn on
;;;    sf:*color*      their fallback colour index
;;;    sf:*shade-lo*   RGB of the SMALLEST preview        (light green)
;;;    sf:*shade-hi*   RGB of the LARGEST                 (dark green)
;;;    sf:*trans*      how transparent a preview is, per cent
;;;    sf:*ltype*      the extras' linetype, created if missing
;;;    sf:*ltscale*    per-arc linetype scale, nil = the drawing's
;;;    sf:*guide*      T to run a dashed line out to a corner the
;;;                    picked lines stop short of
;;;    sf:*gapmin*     how far short one has to stop before it does
;;;    sf:*label*      T to letter each preview R6, R12 ...
;;;    sf:*txthgt*     height of those labels
;;;    sf:*rung*       how far each label climbs past the one before,
;;;                    in text heights
;;;    sf:*dimlayer*   layer the radius dimension goes on ("DIMENSION")
;;;    sf:*smalldim*   radii under this are dimensioned in ...
;;;    sf:*smallstyle* ... this dim style, when the drawing has it
;;;    sf:*dimoff*     how far past the arc the dimension text sits,
;;;                    nil = one radius, and never less than 12
;;;    sf:*dimrepeat*  T to dimension every repeat corner too
;;;    sf:*typ*        T to re-letter the one dimension "<> Typ." once
;;;                    a repeat has been cut at the same radius
;;;
;;;  Notes
;;;    * Two straight LINEs only.  A polyline corner is not filleted --
;;;      the routine says so and asks again; explode it first.
;;;    * Which side of each line survives comes from where it was
;;;      clicked, as in FILLET.  Click near the corner and both legs
;;;      keep the end you clicked toward.
;;;    * A radius only makes the list when its tangent point lands on
;;;      both legs (times sf:*fit*, so a fillet never eats a leg whole).
;;;      A corner too short for even R3 -- the smallest on offer --
;;;      is reported, not filleted.
;;;    * The preview arcs are real entities on their own layer, erased
;;;      on the way out -- on a clean finish, on Esc, and on an error.
;;;      The empty layer is left behind; deleting it is a PURGE away.
;;;      The dashed guides out to a far-off corner are previews too and
;;;      go the same way; the run says so out loud when it draws them,
;;;      because two new lines in a drawing are work until somebody is
;;;      told otherwise.
;;;    * A preview's LABEL is the same answer as its arc.  Both are on
;;;      the list a click is looked up in, so R6 and the arc it letters
;;;      pick the same corner; a guide line is on neither list and a
;;;      click on one is a miss.
;;;    * The shades are true colours (DXF 420) and the transparency is
;;;      DXF 440, both per entity.  A viewport with transparency display
;;;      switched off (TRANSPARENCYDISPLAY 0) draws them solid, which
;;;      costs the fan nothing but the see-through -- the shades and the
;;;      labels still tell the arcs apart.
;;;    * OSMODE, CMDECHO, CLAYER, FILLETRAD, TRIMMODE and the current
;;;      dimension style are all put back the way they were.
;;;    * FILLET does not give up when it refuses a pick -- it asks
;;;      AGAIN -- and DIMRADIUS does the same with a location it will
;;;      not take.  Either one left waiting swallows whatever is sent
;;;      next, so both are followed by a bounded cancel (AUTOBEAD's
;;;      autobead-flush idiom).  Without it a refused radius took the
;;;      dimension, the style restore and the undo close down with it,
;;;      and the run died one step after the click that was meant to
;;;      cut the corner.
;;;    * The undo group is closed only when one was OPENED: with undo
;;;      recording off (UNDOCTL bit 1 clear) none is, and an _End on
;;;      nothing is an error of its own -- landing at the end of the
;;;      run, with the corner already cut and the settings restore
;;;      behind it never reached.
;;; ======================================================================

(setq *smartfillet-version* "v1.11")  ; announced on load; release_lisp.py
                                     ; reads this banner and stamps the
                                     ; dated twin in releases/ from it

;;; -------------------- shop terms --------------------------------------
;;;  Wording this tool writes INTO THE DRAWING that a shop may spell its
;;;  own way -- the knobs that read one say which.  The shop's spelling
;;;  is the profile value CalofinTerm-<ID>, set from LAZTUNE's Terms
;;;  page; with none, the shipped one.  Read as the file loads, so the
;;;  reader sits here, ABOVE the knobs that call it (the grouped build
;;;  takes it from CALOFIN-LIB.lsp as cal:term).  Only drawing text is
;;;  ever a term: keywords and prompts are answered by forms, the
;;;  palette and LAZDIAG's replays by their exact spelling.  The table
;;;  of terms is tools/terms.py.
;;; -------------------- tunables ------------------------------------

(setq sf:*first*      6.0)   ; the smallest radius offered, and the step
(setq sf:*step*       6.0)   ; between the ones after it -- 6" of radius
                             ; is the smallest difference that reads on
                             ; a pool plan
(setq sf:*extras*    '(3.0 9.0)) ; radii offered BESIDES that series.
                             ; A 3 or a 9 turns up, just not often
                             ; enough to be the step; they are drawn
                             ; dashed so the fan still reads as "6s,
                             ; and these two".  nil = the series alone
(setq sf:*maxshown*   10)    ; how many previews may be on screen at
                             ; once; nil = every radius that fits, which
                             ; on a long wall is a great many.  10 is
                             ; the 8 sixes that used to show plus the
                             ; two extras, so nothing was lost to them
(setq sf:*fit*        0.98)  ; how much of the shorter leg a fillet may
                             ; use up: 1.0 would put the tangent point
                             ; exactly on the far end and leave a
                             ; zero-length line behind
(setq sf:*layer*      "SMART FILLET PREVIEW")
(setq sf:*color*      3)     ; the layer's colour, and the fallback
                             ; index on every preview: green, so a
                             ; preview reads as a preview even where a
                             ; true colour cannot be shown
(setq sf:*shade-lo*  '(190 255 190)) ; the SMALLEST preview's green ...
(setq sf:*shade-hi*  '(0 110 0))     ; ... and the largest's.  The fan
                             ; is graded between the two, so which arc
                             ; a label belongs to is a matter of shade
                             ; rather than of tracing it by eye.  Both
                             ; stay green on black; a light-background
                             ; drawing wants the pair swapped round.
                             ; Either one nil = no true colour at all,
                             ; and the fan reads as the layer's own
                             ; colour above
(setq sf:*trans*      40)    ; per cent transparency on every preview,
                             ; so an arc crossing another still reads.
                             ; 0 or nil = solid; over 90 is a preview
                             ; nobody can see
(setq sf:*ltype*      "DASHED")
(setq sf:*ltscale*    0.25)  ; the stock DASHED pattern is 18 units
                             ; long, so a 6" fillet arc (9 units of it)
                             ; would come out as one unbroken dash; a
                             ; quarter-scale pattern puts real gaps in
                             ; even the smallest preview.  nil = leave
                             ; the arcs at the drawing's own LTSCALE
;; Two lines that stop short of where they MEET put the whole fan out
;; in space: FILLET extends them to a corner that is on neither line, so
;; the arcs are drawn round a point yards from anything the drafter can
;; see.  A dashed run from each leg's own end out to that corner is what
;; ties the fan back to the two lines it belongs to.
(setq sf:*guide*      t)     ; nil = never draw one, and a far-off
                             ; corner is a fan of green arcs floating
                             ; in space again
(setq sf:*gapmin*     4.5)   ; how far short of the corner a line has to
                             ; stop before it gets one.  The stock
                             ; DASHED pattern is 18 units and
                             ; sf:*ltscale* takes a quarter of it, so a
                             ; run shorter than 4.5 comes out as one
                             ; unbroken tick on the end of the line --
                             ; which reads as drawn work, the one thing
                             ; a guide must never do.  nil = a guide for
                             ; any gap at all
(setq sf:*label*      t)
(setq sf:*txthgt*     4.0)   ; small enough that two labels a 6" step
                             ; apart clear each other side to side
(setq sf:*rung*       1.4)   ; and each one climbs this many text
                             ; heights further off its leg than the
                             ; label before it on that side, so they
                             ; cannot collide however tight the steps
(setq sf:*dimlayer*   "DIMENSION")
(setq sf:*smalldim*   24.0)             ; POOL's small-dimension rule,
(setq sf:*smallstyle* "STANDARD INCHES"); kept so a fillet callout
                                        ; matches the dims beside it
(setq sf:*dimoff*     nil)   ; nil = one radius past the arc
(setq sf:*dimrepeat*  nil)   ; one callout plus "Typ." is how the sheet
                             ; reads; set T to dimension every corner
(setq sf:*typ*        t)
(setq sf:*minang*     0.02)  ; how far off straight (radians) two legs
                             ; must be before there is a corner at all

;;;  ...and the SHOP TERMS it writes into the drawing -- wording, not a
;;;  size.  Each reads the shop's CalofinTerm-<ID> through the term
;;;  reader above, so LAZTUNE's Terms page moves it in every tool that writes
;;;  it at once; the literal is the shipped spelling, and a LAZTUNE
;;;  value set on the knob itself still wins over the shop's.

;; The suffix after the one radius callout that stands for its
;; repeats -- the callout reads "<>" and then this.
(setq sf:*typ-note* (cal:term "typ-note" " Typ."))

;;; -------------------- run-time state -------------------------------
;;; Not knobs: what a run keeps while it runs, ruled off from the block
;;; above so LAZTUNE does not offer them as settings.  A sysvar snapshot
;;; offered as a knob is set again at every panel open, and every run
;;; then skips taking its own and puts that stored value back instead of
;;; the drafter's settings -- or throws on it, from inside the handler.
;;;
;;; The dim style and the undo flag live here, not in the command's
;;; locals, because the command pushes the error mode for its handler's
;;; (command) drain, and under a push AutoCAD resets the evaluator
;;; before *error* runs: the handler sees globals only.  As locals they
;;; read nil there, so a failure left the undo group open and, from
;;; inside the radius dimension, the small style current.  Both are
;;; cleared at the top of every run, before the push, so a run that died
;;; without its handler cannot hand the next one a group to close.

(setq sf:*preview*    nil)   ; every entity drawn as a preview
(setq sf:*picks*      nil)   ; (preview-arc . radius), what a click means
(setq sf:*smallwarned* nil)  ; the missing-style note is said once
(setq sf:*odim*       nil)   ; the dim style the run opened with
(setq sf:*undo-open*  nil)   ; T while this run's undo group is open

;;; -------------------- shared helpers ------------------------------
;;; The generic CALOFIN-LIB helpers this tool leans on.  Here they are
;;; copies under this file's own prefix, so it loads alone with
;;; APPLOAD; in the shared/ twin they are gone and every call site
;;; reads cal: instead.  Bodies identical to the library's.

;;; -------------------- small local helpers -------------------------

;; A number without AutoLISP's trailing zeros: 12, not 12.000000, and
;; 13.5 rather than 13.50 -- a half inch is a size HONEFILLET letters a
;; lot of, and a callout reading R13.50 is one nobody writes by hand.
(defun sf:num (x)
  (cond ((null x) "?")
        ((= x (fix x)) (rtos x 2 0))
        ((= (* 2.0 x) (fix (* 2.0 x))) (rtos x 2 1))
        (t (rtos x 2 2))))

;; "R12", the way a radius is lettered
(defun sf:rlabel (r) (strcat "R" (sf:num r)))

;; "R3", "R3 and R9", "R3, R9 and R15" -- a list of radii read out the
;; way a sentence needs them.
(defun sf:rlist (rads / n i r out)
  (setq n (length rads) i 0 out "")
  (foreach r rads
    (setq out (strcat out
                      (cond ((= i 0) "")
                            ((= i (1- n)) " and ")
                            (t ", "))
                      (sf:rlabel r))
          i   (1+ i)))
  out)

;; of RADS, the ones drawn dashed -- what the report names
(defun sf:shown-extras (rads / r out)
  (foreach r rads (if (sf:extrap r) (setq out (cons r out))))
  (reverse out))

;; An (r g b) triple as the 24-bit integer DXF group 420 wants.
(defun sf:truecol (rgb)
  (+ (* 65536 (fix (car rgb))) (* 256 (fix (cadr rgb))) (fix (caddr rgb))))

;; a + f*(b - a), rounded to a whole colour channel
(defun sf:mix (a b f) (fix (+ 0.5 a (* f (- b a)))))

;; Preview I of N as an (r g b) triple, graded from sf:*shade-lo* to
;; sf:*shade-hi*.  A lone preview takes the light end: there is nothing
;; for it to be darker THAN.
(defun sf:shade (i n / f lo hi)
  (setq lo sf:*shade-lo*
        hi sf:*shade-hi*
        f  (if (> n 1) (/ (float i) (float (1- n))) 0.0))
  ;; Either end set to nil means "no true colour" -- the fan reads as
  ;; the layer's own sf:*color* instead, which is what sf:colgroups
  ;; already does with a nil shade.  nil is the value every other knob
  ;; in the SETTINGS block takes for "leave it to the drawing", and the
  ;; pair is the one a light-background drawing is told to touch, so it
  ;; is the one somebody empties rather than swaps.
  (if (and lo hi)
    (list (sf:mix (float (car   lo)) (float (car   hi)) f)
          (sf:mix (float (cadr  lo)) (float (cadr  hi)) f)
          (sf:mix (float (caddr lo)) (float (caddr hi)) f))))

;; The DXF 440 value for sf:*trans*: 0x02000000 flags the word as a
;; transparency and the low byte is the ALPHA, so 255 is opaque and the
;; per cent has to be turned round.  nil when the previews are solid --
;; an alpha of 255 is not the same as no 440 at all, since the group
;; overrides the layer's own transparency where one is set.
(defun sf:transval ( / a)
  (if (and sf:*trans* (> sf:*trans* 0))
    (progn
      (setq a (fix (+ 0.5 (* 255.0 (- 1.0 (/ (float sf:*trans*) 100.0))))))
      (+ 33554432 (max 0 (min 255 a))))))

;; T for a radius that is not on the 6" series -- one of sf:*extras*.
;; Those are drawn dashed, so the fan says which sizes are the usual
;; step and which are the ones that only come up sometimes.
(defun sf:extrap (r) (if (member r sf:*extras*) t))

;; Make sure the preview linetype exists, with dashes sized for a
;; drawing in inches so they read at pool scale (pf:ensure-dashed,
;; abhd.lsp:1566).  A drawing that already has one by that name keeps
;; its own.
(defun sf:ensure-ltype ()
  (if (and sf:*ltype* (not (tblsearch "LTYPE" sf:*ltype*)))
    (entmake (list '(0 . "LTYPE") '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLinetypeTableRecord")
                   (cons 2 sf:*ltype*) '(70 . 0)
                   '(3 . "Dashed __ __ __ __ __")
                   '(72 . 65) '(73 . 2) '(40 . 18.0)
                   '(49 . 12.0) '(74 . 0)
                   '(49 . -6.0) '(74 . 0))))
  (if (tblsearch "LTYPE" sf:*ltype*) sf:*ltype* "CONTINUOUS"))

;; the two endpoints of a LINE, in WCS (the entity's own OCS may be
;; tilted, so go through the entity coordinate system)
(defun sf:ends (en / ed)
  (setq ed (entget en))
  (list (cal:2d (trans (cdr (assoc 10 ed)) en 0))
        (cal:2d (trans (cdr (assoc 11 ed)) en 0))))

;;; -------------------- the corner ----------------------------------

;; One leg of the corner: which way the line runs from the crossing
;; point X on the side that was CLICKED -- the side FILLET keeps -- how
;; far it reaches that way, and how far short of X it STARTS.  Returns
;; (unit-direction reach gap), or nil when the line has no length.  The
;; pick decides the direction and the far endpoint decides the reach,
;; so a line whose crossing point lies off its own end (the case FILLET
;; handles by extending it) is measured the same way as one the corner
;; sits inside.  The GAP is what that case costs the drawing: the run
;; from X back to the nearer end, which is line FILLET will make and
;; nobody can see yet, and 0 for a line the corner already sits on.
(defun sf:leg (en x pk / ends a b d s u av nv)
  (setq ends (sf:ends en)
        a    (car  ends)
        b    (cadr ends)
        d    (cal:unit (cal:v- b a)))
  (if d
    (progn
      (setq s (cal:dot d (cal:v- pk x)))
      ;; clicked on the corner itself, where neither side is nearer:
      ;; take the end with more line behind it, the only one a fillet
      ;; could stand on
      (if (< (abs s) 1e-6)
        (setq s (if (>= (cal:dist a x) (cal:dist b x))
                  (cal:dot d (cal:v- a x))
                  (cal:dot d (cal:v- b x)))))
      (setq u  (if (< s 0.0) (cal:v* d -1.0) d)
            av (max (cal:dot u (cal:v- a x)) (cal:dot u (cal:v- b x)))
            nv (min (cal:dot u (cal:v- a x)) (cal:dot u (cal:v- b x))))
      ;; a nearer end BEHIND X is a corner the line already covers, and
      ;; there is no gap to draw over: the negative reach is not a
      ;; distance, so it comes back as the 0 it means
      (if (> av 1e-9) (list u av (max 0.0 nv))))))

;; Everything about the corner two picked lines make, worked out once:
;;   (X u1 reach1 u2 reach2 half-angle gap1 gap2)
;; X is where the two lines cross (extended if they have to be, as
;; FILLET extends them), each u runs from X along the side that was
;; clicked, and half-angle is half the turn between them -- the one
;; number the whole fillet is built from.  The two gaps say how far
;; short of X each line stops, which is the ground the dashed guides
;; are drawn over and 0 for a line X sits on.  nil when there is no
;; corner: parallel lines, the same line twice, or two legs so nearly
;; straight through that no arc could join them.
(defun sf:corner (e1 pk1 e2 pk2 / a b x l1 l2 th)
  (setq a (sf:ends e1)
        b (sf:ends e2)
        x (inters (car a) (cadr a) (car b) (cadr b) nil))
  (if x
    (progn
      (setq x  (cal:2d x)
            l1 (sf:leg e1 x pk1)
            l2 (sf:leg e2 x pk2))
      (if (and l1 l2)
        (progn
          (setq th (abs (cal:signed-dang (angle '(0.0 0.0) (car l1))
                                        (angle '(0.0 0.0) (car l2)))))
          (if (and (> th sf:*minang*) (< th (- pi sf:*minang*)))
            (list x (car l1) (cadr l1) (car l2) (cadr l2) (/ th 2.0)
                  (caddr l1) (caddr l2))))))))

;; How far leg N (1 or 2) stops SHORT of the corner, when that is far
;; enough to be worth a guide.  nil for a line the corner sits on, and
;; nil for one that misses it by less than sf:*gapmin*, where the run
;; out to it would be a tick on the end of a line rather than a line
;; going somewhere.  sf:*guide* nil turns the whole thing off, and
;; then every caller of this is a no-op rather than each of them
;; testing the flag for itself.
(defun sf:gapof (geo n / g)
  (setq g (nth (if (= n 1) 6 7) geo))
  (if (and sf:*guide* g (> g (if sf:*gapmin* sf:*gapmin* 0.0))) g))

;; What those dashed runs ARE, in words, said once a run.  A straight
;; dashed line lands on screen beside dashed ARCS that mean something
;; else entirely, and a drafter who finds two new lines in the drawing
;; has to be told they are a guide rather than work somebody's tool
;; left behind.  nil when both lines reach their corner and none was
;; drawn -- there is nothing to explain then, and the note would be
;; one more line to scroll past.
(defun sf:gapnote (geo / g1 g2)
  (setq g1 (sf:gapof geo 1)
        g2 (sf:gapof geo 2))
  (cond
    ((and g1 g2)
     (strcat "\nNeither line reaches that corner -- they stop "
             (sf:num g1) "\" and " (sf:num g2) "\" short of it."
             "  The dashed STRAIGHT run out to it is a guide, not"
             " drawn work; FILLET extends the legs when the corner is"
             " cut."))
    ((or g1 g2)
     (strcat "\nOne line stops " (sf:num (if g1 g1 g2)) "\" short of"
             " that corner.  The dashed STRAIGHT run out to it is a"
             " guide, not drawn work; FILLET extends that leg when the"
             " corner is cut."))))

;; how far back from the corner a fillet of radius R starts
(defun sf:tanlen (half r) (/ r (cal:tan half)))

;; The biggest radius this corner can take: the tangent point has to
;; land on both legs, and sf:*fit* keeps it clear of the far end so a
;; fillet never eats a leg whole.
(defun sf:rmax (geo)
  (* sf:*fit* (min (caddr geo) (nth 4 geo)) (cal:tan (nth 5 geo))))

;; centre and the two tangent points of the fillet arc of radius R
(defun sf:arcpts (geo r / x u1 u2 half tl)
  (setq x    (car geo)
        u1   (cadr geo)
        u2   (cadddr geo)
        half (nth 5 geo)
        tl   (sf:tanlen half r))
  (list (cal:v+ x (cal:v* (cal:unit (cal:v+ u1 u2)) (/ r (sin half))))
        (cal:v+ x (cal:v* u1 tl))
        (cal:v+ x (cal:v* u2 tl))))

;; EVERY radius this corner takes, ascending: sf:*first* up in
;; sf:*step*s, with sf:*extras* merged in wherever they land.  An extra
;; that is already on the series (a re-tuned sf:*first* of 3, say) is
;; weeded out here, by value.  vl-sort keeps two equal REALS -- it only
;; throws out EQ items, and two reals made apart are not EQ -- so the
;; corner was offered the same radius twice: two previews drawn over
;; each other, each spending one of the sf:*maxshown* slots a real
;; size should have had.
(defun sf:fitting (rmax / r out prev keep)
  (setq r sf:*first*)
  (while (<= r rmax)
    (setq out (cons r out)
          r   (+ r sf:*step*)))
  (foreach r sf:*extras*
    (if (and (> r 0.0) (<= r rmax)) (setq out (cons r out))))
  (foreach r (vl-sort out '<)
    (if (not (and prev (equal r prev 1e-9)))
      (setq keep (cons r keep)))
    (setq prev r))
  (reverse keep))

;; the ones actually drawn: the first sf:*maxshown* of them
(defun sf:candidates (rmax / all r out n)
  (setq all (sf:fitting rmax)
        n   0)
  (foreach r all
    (if (or (null sf:*maxshown*) (< n sf:*maxshown*))
      (setq out (cons r out)
            n   (1+ n))))
  (reverse out))

;; how many would have fitted if nothing capped the list -- what the
;; cap hid has to be said out loud, or 10 previews read as "that is all
;; this corner takes"
(defun sf:howmany (rmax) (length (sf:fitting rmax)))

;; The smallest radius anything would offer, extras included.  A corner
;; under it is the one the routine has nothing to draw for, and since
;; sf:*extras* holds a 3 that is no longer the same number as
;; sf:*first*.
(defun sf:smallest ( / m r)
  (setq m sf:*first*)
  (foreach r sf:*extras* (if (and (> r 0.0) (< r m)) (setq m r)))
  m)

;;; -------------------- previews ------------------------------------

;; Remember what was drawn: everything goes on the erase list, and
;; anything that STANDS FOR a radius -- the arc and the label beside it
;; both -- also goes on the list a click is looked up in.  A guide line
;; is marked with no radius: it is drawn with the fan and erased with
;; it, but it is not one of the answers.
(defun sf:mark (en r)
  (if en
    (progn
      (setq sf:*preview* (cons en sf:*preview*))
      (if r (setq sf:*picks* (cons (cons en r) sf:*picks*)))))
  en)

;; the radius a preview stands for -- its arc or its label, since
;; either one is that size -- and nil for anything else in the drawing,
;; a guide line of this tool's own included
(defun sf:radof (en / p)
  (setq p (assoc en sf:*picks*))
  (if p (cdr p)))

;; Take every preview back out of the drawing.  Called on the way out
;; of the command however it ends -- a preview left behind would be
;; read as drawn work by every other tool in the toolset.
(defun sf:clear ( / e)
  (foreach e sf:*preview* (if (and e (entget e)) (entdel e)))
  (setq sf:*preview* nil
        sf:*picks*   nil))

;; The colour groups every preview entity carries: its own shade as a
;; true colour, and the transparency if there is one.  Kept in one
;; place so an arc and its label cannot end up different colours.
(defun sf:colgroups (col / out tr)
  (setq tr (sf:transval))
  (if col (setq out (list (cons 420 (sf:truecol col)))))
  (if tr (setq out (append out (list (cons 440 tr)))))
  out)

;; One preview arc in COL, drawn the short way round between its two
;; tangent points (a fillet arc is always less than a half circle).
;; DASH draws it in sf:*ltype* rather than solid -- what marks out a
;; radius that is not on the 6" series.
(defun sf:draw-arc (c r p1 p2 col dash / a1 a2 dxf)
  (setq a1 (angle c p1)
        a2 (angle c p2))
  (if (> (cal:angnorm (- a2 a1)) pi)
    (setq a1 (angle c p2)
          a2 (angle c p1)))
  ;; the colour, the linetype and its scale are AcDbEntity properties,
  ;; so they go in the entity section -- ahead of the first subclass
  ;; marker, where DXF puts them -- rather than trailing the arc's own
  ;; geometry.  (append ignores a nil, which is what the two (if ...)s
  ;; hand it when there is nothing to add.)
  (setq dxf (append
              (list '(0 . "ARC") '(100 . "AcDbEntity")
                    (cons 8 sf:*layer*) (cons 62 sf:*color*)
                    (cons 6 (if dash (sf:ensure-ltype) "Continuous")))
              (if (and dash sf:*ltscale*) (list (cons 48 sf:*ltscale*)))
              (sf:colgroups col)
              (list '(100 . "AcDbCircle")
                    (list 10 (car c) (cadr c) 0.0)
                    (cons 40 r)
                    '(100 . "AcDbArc")
                    (cons 50 a1) (cons 51 a2))))
  (if (entmake dxf) (entlast)))

;; One guide line, dashed, and a preview in every other way: the same
;; layer, the same fallback colour, the same transparency, erased with
;; the rest.  No true colour of its own -- the light-to-dark grading is
;; how the fan says WHICH radius, and a guide stands for none of them,
;; so it reads as the layer's plain green.
(defun sf:draw-line (p1 p2 / dxf)
  (setq dxf (append
              (list '(0 . "LINE") '(100 . "AcDbEntity")
                    (cons 8 sf:*layer*) (cons 62 sf:*color*)
                    (cons 6 (sf:ensure-ltype)))
              (if sf:*ltscale* (list (cons 48 sf:*ltscale*)))
              (sf:colgroups nil)             ; entity section, as above
              (list '(100 . "AcDbLine")
                    (list 10 (car p1) (cadr p1) 0.0)
                    (list 11 (car p2) (cadr p2) 0.0))))
  (if (entmake dxf) (entlast)))

;; the radius, lettered beside a preview in that preview's own shade.
;; Middle-centre justified, so the text sits on the point it is given
;; whatever it says.
(defun sf:draw-label (p str col / h dxf)
  (setq h   (if sf:*txthgt* sf:*txthgt* 6.0)
        dxf (append
              (list '(0 . "TEXT") '(100 . "AcDbEntity")
                    (cons 8 sf:*layer*) (cons 62 sf:*color*))
              (sf:colgroups col)              ; entity section, as above
              (list '(100 . "AcDbText")
                    (list 10 (car p) (cadr p) 0.0)
                    (cons 40 h) (cons 1 str)
                    '(72 . 1)                        ; centred across
                    (list 11 (car p) (cadr p) 0.0)
                    '(100 . "AcDbText")
                    '(73 . 2))))                     ; and down
  (if (entmake dxf) (entlast)))

;; Where preview I's label goes: straight out from its tangent point,
;; away from the arc -- so it never lands on the line it belongs to --
;; and one rung further than the label before it on that same leg.
;; Labels alternate legs, so the rung climbs every OTHER preview; the
;; two together are what stops R30 landing on R36.
(defun sf:labelpt (anchor c i / h)
  (setq h (if sf:*txthgt* sf:*txthgt* 6.0))
  (cal:v+ anchor
         (cal:v* (cal:unit (cal:v- anchor c))
                (* h (+ 0.9 (* (if sf:*rung* sf:*rung* 0.0)
                               (float (/ i 2)))))))) ; integer divide:
                                                     ; the rung number

;; The dashed run from each leg's own end out to the corner, for a leg
;; whose line stops short of it.  Two lines that meet on paper get none
;; of this and want none; two that are yards apart get the one thing
;; that says which corner the fan belongs to, because the point FILLET
;; will extend them to is on neither of them.  Marked with no radius --
;; a guide stands for no size, so a click on one is a miss like any
;; other click on empty paper.
(defun sf:guides (geo / u g i)
  (setq i 1)
  (foreach u (list (cadr geo) (cadddr geo))
    (if (setq g (sf:gapof geo i))
      (sf:mark (sf:draw-line (cal:v+ (car geo) (cal:v* u g)) (car geo))
               nil))
    (setq i (1+ i))))

;; Draw the whole fan of previews, light shade to dark, over the dashed
;; guides out to a corner the lines stop short of.  Labels alternate
;; between the two legs: consecutive tangent points sit one step apart
;; along one leg, which is not room enough for two labels side by
;; side.
(defun sf:preview (geo rads / i n r a c t1 t2 anchor col)
  (setq i 0
        n (length rads))
  (cal:ensure-layer sf:*layer* sf:*color*)
  ;; the guides go down FIRST, so every arc sits on top of them: where a
  ;; tangent point lands inside a gap the arc lies along the guide, and
  ;; the arc is what a click there has to find
  (sf:guides geo)
  (foreach r rads
    (setq a   (sf:arcpts geo r)
          c   (car   a)
          t1  (cadr  a)
          t2  (caddr a)
          col (sf:shade i n))
    (sf:mark (sf:draw-arc c r t1 t2 col (sf:extrap r)) r)
    (if sf:*label*
      (progn
        (setq anchor (if (= 0 (rem i 2)) t1 t2))
        ;; the label is marked with the SAME radius as its arc, so
        ;; clicking the R6 is clicking the R6 corner.  It is much the
        ;; bigger target of the two -- an arc is a hairline, and on a
        ;; tight fan the near-miss that used to throw the whole thing
        ;; away is now an answer
        (sf:mark (sf:draw-label (sf:labelpt anchor c i)
                                (sf:rlabel r) col)
                 r)))
    (setq i (1+ i))))

;;; -------------------- asking --------------------------------------

;; One entsel that insists on a LINE.  KW is the single keyword the
;; prompt offers as its way out, and it is also what Enter does -- the
;; bracket text is the keyword itself, so a click on it sends exactly
;; what is tested for, and the <default> says what an empty answer
;; means.  OTHER is the line already picked for this corner, which
;; cannot be picked twice.  Returns (ename pick-point-in-WCS), or nil
;; when the way out is taken.  entsel answers nil to Enter AND to a
;; click that lands just beside a line, and only ERRNO 7 tells them
;; apart.  Taken as Enter, one near miss inside the repeat loop ended
;; the whole "other corners at R?" session and threw away the first
;; line already picked for that corner -- going on meant running the
;; command again, previews, bracket and a second callout for a radius
;; already dimensioned.  ERRNO is sticky, so it is zeroed before every
;; pick, or the Enter after a miss would read as a second miss.
(defun sf:askline (msg kw other / sel ans typ)
  (while (not ans)
    (vl-catch-all-apply 'setvar (list "ERRNO" 0))
    (initget kw)
    (setq sel (entsel (strcat "\n" msg " [" kw "] <" kw ">: ")))
    (if lzd:ask (lzd:ask (getvar "LASTPROMPT") sel) sel)
    (if lzd:watch (lzd:watch sel) sel)
    (cond
      ((= (type sel) 'STR) (setq ans 'SF-NONE))
      ((and (null sel) (= 7 (getvar "ERRNO")))
       (princ (strcat "\n  (nothing there -- click a LINE, or press Enter for "
                      kw ")")))
      ((null sel) (setq ans 'SF-NONE))
      ((and other (eq (car sel) other))
       (princ "\n  (that is the line you just picked -- click the OTHER leg)"))
      ((not (= "LINE" (setq typ (cdr (assoc 0 (entget (car sel)))))))
       (princ (strcat "\n  (that is a " typ " -- SMARTFILLET rounds the"
                      " corner between two straight LINEs; explode a"
                      " polyline first)")))
      (t (setq ans (list (car sel) (cal:2d (trans (cadr sel) 1 0)))))))
  (if (eq ans 'SF-NONE) nil ans))

;; Which preview was clicked, as its radius.  nil when the user gives
;; up on the corner.  This one has no <default>, so Enter re-asks
;; (STANDARDS.md section 1 rule 5): the arcs are thin and the near-miss
;; that would throw a whole fan of them away is exactly the click this
;; prompt invites.  Cancel is in the bracket, so there is a mouse-only
;; way out that does not depend on hitting anything.
(defun sf:pickpreview ( / msg sel ans r)
  ;; the question in a local: it is asked in the prompt and written down
  ;; again in the transcript, and two copies of one string is how the
  ;; two come to say different things
  (setq msg "\nClick the rounded corner you want, or its label [Cancel]: ")
  (while (not ans)
    (initget "Cancel")
    (setq sel (entsel msg))
    (if lzd:ask (lzd:ask msg sel) sel)
    (if lzd:watch (lzd:watch sel) sel)
    (cond
      ((= (type sel) 'STR) (setq ans 'SF-NONE))
      ((null sel)
       (princ (strcat "\n  (nothing there -- click one of the green"
                      " corners or the R-number beside it, or type"
                      " Cancel)")))
      ((setq r (sf:radof (car sel))) (setq ans r))
      (t (princ (strcat "\n  (that is not one of the previews -- click a"
                        " green corner, or the R-number lettered beside"
                        " it)")))))
  (if (eq ans 'SF-NONE) nil ans))

;;; -------------------- cutting and dimensioning --------------------

;; Safety valve, AUTOBEAD's (autobead-flush): an internal command left
;; WAITING for input is still on the command line, and the next
;; (command ...) from here is read as an answer to it rather than as a
;; command of its own.  FILLET is the one that does this -- it refuses a
;; pick and asks again ("Radius is too large", two lines it cannot join)
;; rather than giving up -- and DIMRADIUS does it with a location it
;; will not take.  Left un-cancelled, the run derails one step after the
;; click that was meant to cut the corner: the radius dimension is
;; swallowed as an answer, then the style restore, then the UNDO close,
;; and what the drafter gets is an error where the rest of the corners
;; should have been.
;;
;; A bare (command) CANCELS, where an Enter would only answer the prompt
;; in front of it.  Bounded, for the reason AUTOBEAD gives: one bit of
;; CMDACTIVE means "a dialog is up", which no keystroke from here can
;; clear, and an unbounded loop against that bit hangs AutoCAD with no
;; Esc out.
(defun sf:flush ( / guard)
  (setq guard 0)
  (while (and (> (getvar "CMDACTIVE") 0) (< guard 10))
    (command)
    (setq guard (1+ guard))))

;; Cut the corner for real.  The two picks go to FILLET exactly as the
;; user made them, so the side each line keeps is the side clicked.
;; Returns the arc FILLET made, or nil when it refused.
(defun sf:dofillet (e1 pk1 e2 pk2 r / pre new ed)
  (setq pre (entlast))
  (setvar "FILLETRAD" r)
  (command "_.FILLET" (list e1 (trans pk1 0 1)) (list e2 (trans pk2 0 1)))
  ;; a FILLET that refused a pick is still asking: cancel it here, where
  ;; the refusal costs one message, rather than letting the next command
  ;; answer it
  (sf:flush)
  (setq new (entlast))
  (if (and new (not (eq new pre))
           (setq ed (entget new))
           (= "ARC" (cdr (assoc 0 ed))))
    new))

;; Switch to the small-dimension style for a measurement under
;; sf:*smalldim*, POOL's rule (pool:dimsbegin, POOL.LSP:370), so a
;; fillet callout matches the dims beside it.  Returns the style to go
;; back to, nil when nothing moved.
(defun sf:dimsbegin (d / od)
  (if (< d sf:*smalldim*)
    (if (tblsearch "DIMSTYLE" sf:*smallstyle*)
      (progn
        (setq od (getvar "DIMSTYLE"))
        (if (= (strcase od) (strcase sf:*smallstyle*))
          (setq od nil)                    ; already current
          (command "_.-DIMSTYLE" "_Restore" sf:*smallstyle*))
        od)
      (progn
        (if (not sf:*smallwarned*)
          (progn
            (princ (strcat "\n(no \"" sf:*smallstyle* "\" dim style in"
                           " this drawing -- the radius is dimensioned"
                           " in the current style)"))
            (setq sf:*smallwarned* t)))
        nil))))

(defun sf:dimsend (od)
  (if (and od (tblsearch "DIMSTYLE" od))
    (command "_.-DIMSTYLE" "_Restore" od)))

;; DIMSTYLE is read-only to setvar, so it goes back through a command,
;; and command-s so the same call is legal from inside *error*.
(defun sf:restyle (odim)
  (if (and odim (tblsearch "DIMSTYLE" odim)
           (not (equal odim (getvar "DIMSTYLE"))))
    (vl-catch-all-apply 'command-s
                        (list "_.-DIMSTYLE" "_Restore" odim))))

;; Put the radius dimension on the arc just cut: leader out from the
;; arc along the line from its centre through the corner, which is the
;; one direction that is clear of both legs.  The centre comes from the
;; geometry the arc was cut to rather than back out of the arc -- they
;; are the same point, and the one we already hold cannot be read out
;; of a tilted OCS wrong.  Returns the dimension.
(defun sf:dimarc (arc r geo / c x out on loc od pre new)
  (setq c   (car (sf:arcpts geo r))
        x   (car geo)
        out (cal:unit (cal:v- x c)))
  (if out
    (progn
      (setq on  (cal:v+ c (cal:v* out r))
            loc (cal:v+ c (cal:v* out (+ r (if sf:*dimoff*
                                           sf:*dimoff*
                                           (max r 12.0)))))
            pre (entlast))
      (setvar "CLAYER" (cal:ensure-layer sf:*dimlayer* 2))
      (setq od (sf:dimsbegin r))
      (command "_.DIMRADIUS" (list arc (trans on 0 1))
               "_non" (trans loc 0 1))
      ;; the same valve: a DIMRADIUS still asking would swallow the
      ;; style restore below and leave the run dimensioning in the
      ;; small style
      (sf:flush)
      (sf:dimsend od)
      (setq new (entlast))
      (if (and new (not (eq new pre))) new))))

;; Re-letter a radius callout as typical.  The radius is called out
;; once and the repeats read "Typ.", the way a drafter letters it -- and
;; whether there WERE repeats is not known until the loop has run, so
;; the note is added afterwards rather than guessed at.  "<>" is
;; AutoCAD's stand-in for the measurement, so the dimension goes on
;; measuring itself.
(defun sf:typit (dim / ed)
  (if (and dim (setq ed (entget dim)))
    (progn
      (setq ed (if (assoc 1 ed)
                 (subst (cons 1 (strcat "<>" sf:*typ-note*)) (assoc 1 ed) ed)
                 (append ed (list (cons 1 (strcat "<>" sf:*typ-note*))))))
      (entmod ed)
      (entupd dim))))

;; The rest of the corners, at the radius already settled on: two lines
;; each until Done.  Returns how many were cut.
(defun sf:repeat (r / n go a b geo arc)
  (setq n 0 go t)
  (while go
    (setq a (sf:askline "Select the first line of the next corner"
                        "Done" nil))
    (setq b (if a (sf:askline "Select the second line of that corner"
                              "Done" (car a))))
    (if (or (null a) (null b))
      (setq go nil)
      (progn
        (setq geo (sf:corner (car a) (cadr a) (car b) (cadr b)))
        (cond
          ((null geo)
           (princ (strcat "\n  (those two never meet at an angle --"
                          " left alone)")))
          ((< (sf:rmax geo) r)
           (princ (strcat "\n  (too short a corner for "
                          (sf:rlabel r) " -- left alone)")))
          ((setq arc (sf:dofillet (car a) (cadr a) (car b) (cadr b) r))
           (setq n (1+ n))
           (if sf:*dimrepeat* (sf:dimarc arc r geo)))
          (t (princ (strcat "\n  (AutoCAD would not fillet that corner"
                            " -- left alone)")))))))
  n)

;;; -------------------- the command ---------------------------------

(defun c:SMARTFILLET ( / *error*
                         one two geo rmax rads extra shown-extras note
                         r arc dim1 made)

  ;; -- restore drawing state on error / Esc.  The previews go first:
  ;;    they are entities like any other, and a run cut short partway
  ;;    would otherwise leave a fan of dashed arcs in the drawing for
  ;;    the next tool to read as work.  Then the user's settings, then
  ;;    the undo group -- left open, the next U would swallow the
  ;;    user's own work
  ;;
  ;;    *error* is a local of this command, so nothing here saves or
  ;;    restores the global one: a copy taken here is the local nil, and
  ;;    under the pushed mode, where the handler sees globals only,
  ;;    writing it back wiped whatever handler another application had
  ;;    installed.  The two run globals are cleared FIRST, before the
  ;;    push, so nothing a dead run left behind is acted on.
  (setq sf:*odim* nil
        sf:*undo-open* nil)
  (defun *error* (m)
    (sf:clear)
    (cal:sysrestore)
    ;; An Esc part-way through FILLET or DIMRADIUS leaves that command
    ;; pending, and the two command calls BELOW this line -- the style
    ;; restore and the undo close -- would be read as answers to it.  So
    ;; the valve comes first here, before either of them.  (command) is
    ;; only legal from inside *error* behind *push-error-using-command*,
    ;; which the command pushes on the way in.
    (sf:flush)
    ;; the error mode comes off HERE, after the last bare (command) and
    ;; before the first command-s: under a push AutoCAD refuses command-s
    ;; inside *error* with "INTERNAL error in FAIL", past any
    ;; vl-catch-all-apply, and the rest of the handler never runs
    (if *pop-error-mode* (*pop-error-mode*))
    (sf:restyle sf:*odim*)
    (setq sf:*odim* nil)
    (if sf:*undo-open*
      (progn
        (vl-catch-all-apply 'command-s (list "_.UNDO" "_End"))
        (setq sf:*undo-open* nil)))
    (if (and m (not (wcmatch (strcase m)
                             "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nSMARTFILLET error: " m)))
    (if lzd:report (lzd:report "SMARTFILLET" *smartfillet-version* m))
    (princ))
  (if lzd:begin (lzd:begin "SMARTFILLET" *smartfillet-version*))

  ;; AutoCAD 2012+ requires this before *error* may call a bare
  ;; (command), and the handler above has one: the sf:flush drain.  The
  ;; style restore and the undo close after it are command-s, issued
  ;; once the handler has popped the mode.  A harmless no-op guard on
  ;; older releases, where it does not exist
  (if *push-error-using-command* (*push-error-using-command*))

  (vl-load-com)
  (cal:syssave '("OSMODE" "CMDECHO" "CLAYER" "FILLETRAD" "TRIMMODE"))
  (setq sf:*odim* (getvar "DIMSTYLE")
        made 0)
  (setvar "CMDECHO" 0)
  (setvar "OSMODE"  0)
  (setvar "TRIMMODE" 1)                    ; a fillet that leaves the
                                           ; old corner standing is not
                                           ; what anyone means by one

  ;; -- 1. the corner: two lines, each clicked on the side to keep
  (setq one (sf:askline "Select the first line of the corner" "Cancel" nil))
  (if one
    (setq two (sf:askline "Select the second line of the corner"
                          "Cancel" (car one))))
  (setq geo (if (and one two)
              (sf:corner (car one) (cadr one) (car two) (cadr two))))

  (cond
    ((not (and one two))
     (princ "\nSMARTFILLET cancelled -- nothing drawn."))

    ((null geo)
     (princ (strcat "\nThose two lines make no corner -- they are"
                    " parallel, or they run straight through one"
                    " another.  Nothing to round.")))

    ((< (setq rmax (sf:rmax geo)) (sf:smallest))
     (princ (strcat "\nThe shorter leg of that corner only allows "
                    (sf:rlabel rmax) " -- less than the smallest"
                    " preview (" (sf:rlabel (sf:smallest)) ").  Nothing"
                    " drawn; lower sf:*first* to work at that size.")))

    (t
     ;; -- 2. one undo group over the previews and everything they lead
     ;;       to, so a single U undoes the lot
     ;; only when undo is recording - _Begin in a drawing with UNDO
     ;; off (bit 1 of UNDOCTL clear) errors out of the command
     (if (= 1 (logand 1 (getvar "UNDOCTL")))
       (progn
         (command "_.UNDO" "_Begin")
         (setq sf:*undo-open* t)))
     (setq 
           rads      (sf:candidates rmax)
           extra     (- (sf:howmany rmax) (length rads)))
     (sf:preview geo rads)
     (princ (strcat "\n" (itoa (length rads)) " corner"
                    (if (= 1 (length rads)) "" "s")
                    " that fit, light to dark: " (sf:rlabel (car rads))
                    (if (cdr rads)
                      (strcat " to " (sf:rlabel (last rads)))
                      "")
                    "."))
     ;; which arcs are dashed is a fact about the SIZES, not about the
     ;; drawing, so it is said rather than left to be inferred from the
     ;; one preview that looks different
     (setq shown-extras (sf:shown-extras rads))
     (if shown-extras
       (princ (strcat "\nDashed: " (sf:rlist shown-extras)
                      " -- the in-between sizes, less common than a "
                      (sf:num sf:*step*) "\" step.")))
     ;; ...and a STRAIGHT dashed line, when there is one, is not one of
     ;; those at all.  It goes out to a corner the picked lines stop
     ;; short of, which is where the whole fan is drawn and where
     ;; neither line can be seen -- said here, next to the sentence
     ;; about the dashed arcs, because that is the one it would
     ;; otherwise be read as
     (if (setq note (sf:gapnote geo)) (princ note))
     ;; a cap that says nothing reads as "that is all this corner
     ;; takes", which is a different fact
     (if (> extra 0)
       (princ (strcat "\n" (itoa extra) " larger radi"
                      (if (= 1 extra) "us" "i") " also fit"
                      (if (= 1 extra) "s" "") " and "
                      (if (= 1 extra) "is" "are") " not shown"
                      " -- raise sf:*maxshown* to see "
                      (if (= 1 extra) "it" "them") ".")))
     ;; the label answers for its arc, and on a fan this tight it is
     ;; the bigger target of the two -- worth saying, because nothing
     ;; on screen suggests a piece of text is clickable
     (if sf:*label*
       (princ (strcat "\nClick an arc or the R-number beside it --"
                      " either one is that radius.")))

     ;; -- 3. the one that gets cut
     (setq r (sf:pickpreview))
     (sf:clear)
     (cond
       ((null r)
        (princ "\nNothing picked -- the corner is as it was."))
       ((null (setq arc (sf:dofillet (car one) (cadr one)
                                     (car two) (cadr two) r)))
        (princ (strcat "\nAutoCAD would not fillet that corner at "
                       (sf:rlabel r) " -- the lines are as they were.")))
       (t
        (setq made 1
              dim1 (sf:dimarc arc r geo))
        (princ (strcat "\n" (sf:rlabel r) " corner cut and dimensioned"
                       (if dim1 (strcat " on layer " sf:*dimlayer*) "")
                       "."))

        ;; -- 4. the same radius, for the rest of the corners
        (if (cal:askyn (strcat "Fillet other corners at "
                              (sf:rlabel r) "?")
                      "Yes" nil)
          (setq made (+ made (sf:repeat r))))
        (if (and sf:*typ* dim1 (> made 1)) (sf:typit dim1))

        (princ (strcat "\n" (itoa made) " corner"
                       (if (= 1 made) "" "s") " filleted at "
                       (sf:rlabel r)
                       (if (and sf:*typ* (> made 1) dim1)
                         (strcat " -- the one dimension now reads "
                                 ;; one space, whether or not the
                                 ;; shop's term begins with one
                                 (vl-string-trim " " sf:*typ-note*))
                         "")
                       "."))))

     ;; close only a group this run opened: with undo recording off
     ;; (UNDOCTL bit 1 clear) none was, and an _End on nothing is an
     ;; error of its own -- and it lands HERE, with the corner already
     ;; cut and the settings restore below it never reached
     (if sf:*undo-open*
       (progn
         (command "_.UNDO" "_End")
         (setq sf:*undo-open* nil)))))

  ;; every path out drops the snapshot, the quiet ones included: a run
  ;; that found nothing to do and kept its snapshot would hand it to the
  ;; NEXT run, which would then put the user's settings back to what
  ;; they were two commands ago
  (sf:restyle sf:*odim*)
  (setq sf:*odim* nil)
  (cal:sysrestore)
  ;; ...and so does the error mode pushed at the top: every quiet exit
  ;; and the cut one come through here, and a mode left stacked refuses
  ;; command-s inside every later handler in the session (AutoLISP
  ;; reference, *push-error-using-command*)
  (if *pop-error-mode* (*pop-error-mode*))
  (if lzd:end (lzd:end "SMARTFILLET"))
  (princ))

(defun c:SMARTFILLETVER ()
  (princ (strcat "\nSMARTFILLET " *smartfillet-version*))
  (princ))

;; -------------------- self tests ---------------------------------------
;; What LAZDIAG runs on the drafter's machine after this tool fails, and
;; writes into the report: the tool's own helpers on inputs whose answers
;; are KNOWN, so the report says whether the arithmetic was sound where
;; it ran.  (label expression expected) passes when the value is equal
;; to expected (to 1e-6); (label expression) passes when it is not nil,
;; and the value is written down either way.  Nothing here may prompt,
;; draw or (command): it is evaluated from inside *error*.
;; tests/test_selftests.py runs every entry in the VM at both tiers.
(defun sf:selftests ()
  (list
    (list "num letters a whole radius without decimals" '(sf:num 12.0)  "12")
    (list "num keeps a half inch without a trailing zero" '(sf:num 13.5)  "13.5")
    (list "rlist reads three radii out as a sentence"
          '(sf:rlist '(3.0 9.0 15.0))  "R3, R9 and R15")
    (list "shown-extras picks the dashed sizes out of a fan"
          '(sf:shown-extras '(3.0 6.0 9.0 12.0))  '(3.0 9.0))
    (list "mix rounds to a whole colour channel"       '(sf:mix 0.0 100.0 0.5)  50)
    (list "shade: a lone preview takes the light end"
          '(equal (sf:shade 0 1) sf:*shade-lo*)  T)
    (list "tanlen: a 6in fillet on a right angle starts 6in back"
          '(sf:tanlen (/ pi 4.0) 6.0)  6.0)
    (list "rmax of a right angle is the short leg, times the fit"
          '(/ (sf:rmax (list '(0.0 0.0) '(1.0 0.0) 100.0 '(0.0 1.0) 50.0
                             (/ pi 4.0) 0.0 0.0))
              sf:*fit*)
          50.0)
    (list "arcpts: R6 on a right angle at the origin centres at 6,6"
          '(sf:arcpts (list '(0.0 0.0) '(1.0 0.0) 100.0 '(0.0 1.0) 50.0
                            (/ pi 4.0) 0.0 0.0)
                      6.0)
          '((6.0 6.0) (6.0 0.0) (0.0 6.0)))
    (list "fitting: the shipped fan under R20 is 3, 6, 9, 12, 18"
          '(sf:fitting 20.0)  '(3.0 6.0 9.0 12.0 18.0))
    (list "smallest is the 3 extra, not the first of the series"
          '(sf:smallest)  3.0)
    (list "candidates caps a long wall's 18 fitting radii at the 10 shown"
          '(list (sf:howmany 100.0) (length (sf:candidates 100.0)))  '(18 10))))

(foreach c '("SMARTFILLET")
  (setq *calofin-selftests*
        (cons (cons c 'sf:selftests) *calofin-selftests*)))

;; Quiet inside the whole build: LAZPASS.lsp and
;; CALOFIN-LOADER.lsp set the flag while they load their members,
;; because one file's greeting is a greeting and sixty-three of
;; them is a wall the drafter scrolls past in every drawing they
;; open.  APPLOADed alone the flag is nil and this prints, which
;; is the one time somebody wants to be told.  CALVER reports the
;; whole roster whenever it is asked.
(if (not *calofin-quiet*)
  (princ (strcat "\nSMARTFILLET " *smartfillet-version*
                 " loaded -- type SMARTFILLET, pick two lines, and click"
                 " the rounded corner you want, or the R-number beside"
                 " it.")))
(princ)
