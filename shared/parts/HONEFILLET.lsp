;;; ======================================================================
;;; HONEFILLET.lsp  --  the sizes BETWEEN the ones SMARTFILLET offers:
;;;                     bracket two of them and hone at half inches
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  HONEFILLET     preview the radii that fit a corner, pick
;;;                           two neighbours, redraw between them at half
;;;                           inches, cut the one clicked and dimension it
;;;            HONEFILLETVER  print the loaded version
;;;
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;
;;;  SMARTFILLET draws the corner at every 6-inch radius that fits and
;;;  cuts the one clicked.  Most of the time one of those IS the answer.
;;;  Sometimes it is not -- the corner wants something between two of
;;;  them, and the 6-inch step is the wrong ruler for that job.
;;;
;;;  HONEFILLET is that second look.  It is SMARTFILLET as far as the
;;;  fan, and then instead of cutting the one clicked it asks for TWO,
;;;  either side of the size wanted, and redraws just that range in half
;;;  inches.  Click one of those and it is cut and dimensioned exactly as
;;;  SMARTFILLET would have cut a round one.
;;;
;;;    1. Select the two lines that make the corner.  Click each one on
;;;       the side you want KEPT -- exactly how FILLET reads a pick:
;;;       what lies beyond the corner is trimmed away.
;;;    2. The coarse fan is drawn: 6 up in 6s, plus the 3 and the 9 in
;;;       hn:*extras*, every radius that leaves both legs something to
;;;       stand on.  This is the menu to bracket from, not the menu to
;;;       cut from -- nothing here is cut.
;;;    3. Click the two the answer sits BETWEEN.  Neighbours: the range
;;;       has to be short enough to draw at half inches, and a pair too
;;;       far apart is said so and re-asked rather than truncated.
;;;    4. The coarse fan goes and that range comes back in half-inch
;;;       steps, both ends included -- so settling back on the round
;;;       number is still one click.  The whole inches are solid and the
;;;       half inches dashed, which is the fan saying which of them is
;;;       a size somebody will not have to think twice about.
;;;    5. Click the one you want.  The previews go, the corner is
;;;       filleted for real at that radius, and the arc gets its radius
;;;       dimension -- R13.5 lettered as R13.5, not rounded to suit the
;;;       tool that drew it.
;;;    6. It then offers the SAME radius for the rest of the corners:
;;;       two lines per corner until Done.  As soon as one repeat is
;;;       cut, the single dimension becomes "R13.5 Typ.", which is how
;;;       the radius would be lettered by hand.
;;;
;;;  Telling one preview from the next is the whole job of both fans,
;;;  and it matters more here than it does in SMARTFILLET -- half an
;;;  inch of radius is a hair's difference on screen.  So three things
;;;  do it at once: the fan runs light green to dark green with the
;;;  radius, every arc is part transparent so the ones underneath still
;;;  read, and each label is drawn in ITS OWN arc's shade.  The labels
;;;  climb a rung further off the leg with each preview, because
;;;  consecutive tangent points sit half an inch apart along a leg and
;;;  that is nothing like room for two labels side by side.
;;;
;;;  The whole run is one undo group: a single U puts every corner back
;;;  and takes the dimension away.
;;;
;;;  Usage
;;;    Command: HONEFILLET
;;;    Command: HONEFILLETVER   prints the version
;;;
;;;  Tunables (setq them after loading if a drawing needs different
;;;  sizes or names, e.g. in a startup file):
;;;    hn:*first*      smallest radius in the coarse fan   (6.0)
;;;    hn:*step*       step between those                  (6.0)
;;;    hn:*extras*     odd radii offered too, drawn dashed (3 and 9)
;;;    hn:*maxshown*   most coarse previews at once        (10)
;;;    hn:*fine*       the honing step                     (0.5)
;;;    hn:*maxfine*    most honed previews at once, which is also what
;;;                    "neighbouring" is measured against  (14)
;;;    hn:*fit*        fraction of a leg a fillet may eat  (0.98)
;;;    hn:*layer*      layer the previews are drawn on
;;;    hn:*color*      their fallback colour index
;;;    hn:*shade-lo*   RGB of the SMALLEST preview        (light green)
;;;    hn:*shade-hi*   RGB of the LARGEST                 (dark green)
;;;    hn:*trans*      how transparent a preview is, per cent
;;;    hn:*ltype*      the dashed previews' linetype, created if missing
;;;    hn:*ltscale*    per-arc linetype scale, nil = the drawing's
;;;    hn:*label*      T to letter each preview R6, R13.5 ...
;;;    hn:*txthgt*     height of those labels
;;;    hn:*rung*       how far each label climbs past the one before,
;;;                    in text heights
;;;    hn:*dimlayer*   layer the radius dimension goes on ("DIMENSION")
;;;    hn:*smalldim*   radii under this are dimensioned in ...
;;;    hn:*smallstyle* ... this dim style, when the drawing has it
;;;    hn:*dimoff*     how far past the arc the dimension text sits,
;;;                    nil = one radius, and never less than 12
;;;    hn:*dimrepeat*  T to dimension every repeat corner too
;;;    hn:*typ*        T to re-letter the one dimension "<> Typ." once
;;;                    a repeat has been cut at the same radius
;;;
;;;  Notes
;;;    * Two straight LINEs only.  A polyline corner is not filleted --
;;;      the routine says so and asks again; explode it first.
;;;    * Which side of each line survives comes from where it was
;;;      clicked, as in FILLET.  Click near the corner and both legs
;;;      keep the end you clicked toward.
;;;    * A radius only makes the list when its tangent point lands on
;;;      both legs (times hn:*fit*, so a fillet never eats a leg whole).
;;;      A corner too short for even R3 is reported, not filleted.
;;;    * The two picks may come in either order, and a corner honed
;;;      between R12 and R18 can still be cut at R12 or at R18 -- both
;;;      ends are drawn, so the second look never takes the first
;;;      look's answer away.
;;;    * The preview arcs are real entities on their own layer, erased
;;;      on the way out -- on a clean finish, on Esc, and on an error.
;;;      The empty layer is left behind; deleting it is a PURGE away.
;;;    * The shades are true colours (DXF 420) and the transparency is
;;;      DXF 440, both per entity.  A viewport with transparency display
;;;      switched off (TRANSPARENCYDISPLAY 0) draws them solid, which
;;;      costs the fan nothing but the see-through -- the shades and the
;;;      labels still tell the arcs apart.
;;;    * OSMODE, CMDECHO, CLAYER, FILLETRAD, TRIMMODE and the current
;;;      dimension style are all put back the way they were.
;;; ======================================================================

(setq *honefillet-version* "v1.0")  ; announced on load; release_lisp.py
                                     ; reads this banner and stamps the
                                     ; dated twin in releases/ from it

;;; -------------------- tunables ------------------------------------

(setq hn:*first*      6.0)   ; the smallest radius in the COARSE fan --
(setq hn:*step*       6.0)   ; the one that is only there to bracket
                             ; from -- and the step between the ones
                             ; after it.  SMARTFILLET's fan, because
                             ; bracketing from a different set of sizes
                             ; than the one just looked at is a trap
(setq hn:*extras*    '(3.0 9.0)) ; radii offered BESIDES that series.
                             ; A 3 or a 9 turns up, just not often
                             ; enough to be the step; they are drawn
                             ; dashed so the fan still reads as "6s,
                             ; and these two".  nil = the series alone
(setq hn:*maxshown*   10)    ; how many COARSE previews may be on screen
                             ; at once; nil = every radius that fits,
                             ; which on a long wall is a great many
(setq hn:*fine*       0.5)   ; the honing step: what the range between
                             ; the two bracketed sizes is redrawn at.
                             ; Half an inch is where a radius stops
                             ; being a size somebody could have meant
                             ; and starts being a number
(setq hn:*maxfine*    14)    ; most honed previews at once, and so also
                             ; what "neighbouring" MEANS here: a full
                             ; 6" bracket comes to 13 half-inch steps,
                             ; so 14 admits any two neighbours and
                             ; turns away a pair with a whole size
                             ; between them.  Raising it widens what
                             ; may be bracketed; it does not make the
                             ; result any more readable
(setq hn:*fit*        0.98)  ; how much of the shorter leg a fillet may
                             ; use up: 1.0 would put the tangent point
                             ; exactly on the far end and leave a
                             ; zero-length line behind
(setq hn:*layer*      "HONE FILLET PREVIEW")
(setq hn:*color*      3)     ; the layer's colour, and the fallback
                             ; index on every preview: green, so a
                             ; preview reads as a preview even where a
                             ; true colour cannot be shown
(setq hn:*shade-lo*  '(190 255 190)) ; the SMALLEST preview's green ...
(setq hn:*shade-hi*  '(0 110 0))     ; ... and the largest's.  The fan
                             ; is graded between the two, so which arc
                             ; a label belongs to is a matter of shade
                             ; rather than of tracing it by eye.  Both
                             ; stay green on black; a light-background
                             ; drawing wants the pair swapped round
(setq hn:*trans*      40)    ; per cent transparency on every preview,
                             ; so an arc crossing another still reads.
                             ; 0 or nil = solid; over 90 is a preview
                             ; nobody can see
(setq hn:*ltype*      "DASHED")
(setq hn:*ltscale*    0.25)  ; the stock DASHED pattern is 18 units
                             ; long, so a 6" fillet arc (9 units of it)
                             ; would come out as one unbroken dash; a
                             ; quarter-scale pattern puts real gaps in
                             ; even the smallest preview.  nil = leave
                             ; the arcs at the drawing's own LTSCALE
(setq hn:*label*      t)
(setq hn:*txthgt*     3.0)   ; smaller than SMARTFILLET's: R13.5 is two
                             ; characters longer than R12 and the honed
                             ; fan sets them half an inch apart
(setq hn:*rung*       1.4)   ; and each one climbs this many text
                             ; heights further off its leg than the
                             ; label before it on that side, which is
                             ; what carries the honed fan -- side to
                             ; side there is no room at all at half an
                             ; inch a step
(setq hn:*dimlayer*   "DIMENSION")
(setq hn:*smalldim*   24.0)             ; POOL's small-dimension rule,
(setq hn:*smallstyle* "STANDARD INCHES"); kept so a fillet callout
                                        ; matches the dims beside it
(setq hn:*dimoff*     nil)   ; nil = one radius past the arc
(setq hn:*dimrepeat*  nil)   ; one callout plus "Typ." is how the sheet
                             ; reads; set T to dimension every corner
(setq hn:*typ*        t)
(setq hn:*minang*     0.02)  ; how far off straight (radians) two legs
                             ; must be before there is a corner at all

(setq hn:*preview*    nil)   ; every entity drawn as a preview
(setq hn:*picks*      nil)   ; (preview-arc . radius), what a click means
(setq hn:*smallwarned* nil)  ; the missing-style note is said once

;;; -------------------- shared helpers ------------------------------
;;; The generic CALOFIN-LIB helpers this tool leans on.  Here they are
;;; copies under this file's own prefix, so it loads alone with
;;; APPLOAD; in the shared/ twin they are gone and every call site
;;; reads cal: instead.  Bodies identical to the library's.

;;; -------------------- small local helpers -------------------------

;; A number without AutoLISP's trailing zeros: 12, not 12.000000, and
;; 13.5 rather than 13.50 -- the half inch is the size this whole tool
;; exists to letter, and a callout reading R13.50 is one nobody writes
;; by hand.
(defun hn:num (x)
  (cond ((null x) "?")
        ((= x (fix x)) (rtos x 2 0))
        ((= (* 2.0 x) (fix (* 2.0 x))) (rtos x 2 1))
        (t (rtos x 2 2))))

;; "R12", the way a radius is lettered
(defun hn:rlabel (r) (strcat "R" (hn:num r)))

;; "R3", "R3 and R9", "R3, R9 and R15" -- a list of radii read out the
;; way a sentence needs them.
(defun hn:rlist (rads / n i r out)
  (setq n (length rads) i 0 out "")
  (foreach r rads
    (setq out (strcat out
                      (cond ((= i 0) "")
                            ((= i (1- n)) " and ")
                            (t ", "))
                      (hn:rlabel r))
          i   (1+ i)))
  out)

;; of RADS, the ones drawn dashed -- what the report names
(defun hn:shown-extras (rads / r out)
  (foreach r rads (if (hn:extrap r) (setq out (cons r out))))
  (reverse out))

;; An (r g b) triple as the 24-bit integer DXF group 420 wants.
(defun hn:truecol (rgb)
  (+ (* 65536 (fix (car rgb))) (* 256 (fix (cadr rgb))) (fix (caddr rgb))))

;; a + f*(b - a), rounded to a whole colour channel
(defun hn:mix (a b f) (fix (+ 0.5 a (* f (- b a)))))

;; Preview I of N as an (r g b) triple, graded from hn:*shade-lo* to
;; hn:*shade-hi*.  A lone preview takes the light end: there is nothing
;; for it to be darker THAN.
(defun hn:shade (i n / f lo hi)
  (setq lo hn:*shade-lo*
        hi hn:*shade-hi*
        f  (if (> n 1) (/ (float i) (float (1- n))) 0.0))
  (list (hn:mix (float (car   lo)) (float (car   hi)) f)
        (hn:mix (float (cadr  lo)) (float (cadr  hi)) f)
        (hn:mix (float (caddr lo)) (float (caddr hi)) f)))

;; The DXF 440 value for hn:*trans*: 0x02000000 flags the word as a
;; transparency and the low byte is the ALPHA, so 255 is opaque and the
;; per cent has to be turned round.  nil when the previews are solid --
;; an alpha of 255 is not the same as no 440 at all, since the group
;; overrides the layer's own transparency where one is set.
(defun hn:transval ( / a)
  (if (and hn:*trans* (> hn:*trans* 0))
    (progn
      (setq a (fix (+ 0.5 (* 255.0 (- 1.0 (/ (float hn:*trans*) 100.0))))))
      (+ 33554432 (max 0 (min 255 a))))))

;; T for a radius that is not on the 6" series -- one of hn:*extras*.
;; Those are drawn dashed, so the coarse fan says which sizes are the
;; usual step and which are the ones that only come up sometimes.
(defun hn:extrap (r) (if (member r hn:*extras*) t))

;; T for a radius that is not a whole inch.  The honed fan's own
;; dashed-or-solid rule: an R13 is a size, an R13.5 is a decision, and
;; the fan should say which is which without being read.
(defun hn:halfp (r) (if (= r (fix r)) nil t))

;; which rule applies -- FINE is the honed fan, nil the coarse one
(defun hn:dashp (r fine) (if fine (hn:halfp r) (hn:extrap r)))

;; Make sure the preview linetype exists, with dashes sized for a
;; drawing in inches so they read at pool scale (pf:ensure-dashed,
;; abhd.lsp:1566).  A drawing that already has one by that name keeps
;; its own.
(defun hn:ensure-ltype ()
  (if (and hn:*ltype* (not (tblsearch "LTYPE" hn:*ltype*)))
    (entmake (list '(0 . "LTYPE") '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLinetypeTableRecord")
                   (cons 2 hn:*ltype*) '(70 . 0)
                   '(3 . "Dashed __ __ __ __ __")
                   '(72 . 65) '(73 . 2) '(40 . 18.0)
                   '(49 . 12.0) '(74 . 0)
                   '(49 . -6.0) '(74 . 0))))
  (if (tblsearch "LTYPE" hn:*ltype*) hn:*ltype* "CONTINUOUS"))

;; the two endpoints of a LINE, in WCS (the entity's own OCS may be
;; tilted, so go through the entity coordinate system)
(defun hn:ends (en / ed)
  (setq ed (entget en))
  (list (cal:2d (trans (cdr (assoc 10 ed)) en 0))
        (cal:2d (trans (cdr (assoc 11 ed)) en 0))))

;;; -------------------- the corner ----------------------------------

;; One leg of the corner: which way the line runs from the crossing
;; point X on the side that was CLICKED -- the side FILLET keeps -- and
;; how far it reaches that way.  Returns (unit-direction reach), or nil
;; when the line has no length.  The pick decides the direction and the
;; far endpoint decides the reach, so a line whose crossing point lies
;; off its own end (the case FILLET handles by extending it) is
;; measured the same way as one the corner sits inside.
(defun hn:leg (en x pk / ends a b d s u av)
  (setq ends (hn:ends en)
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
            av (max (cal:dot u (cal:v- a x)) (cal:dot u (cal:v- b x))))
      (if (> av 1e-9) (list u av)))))

;; Everything about the corner two picked lines make, worked out once:
;;   (X u1 reach1 u2 reach2 half-angle)
;; X is where the two lines cross (extended if they have to be, as
;; FILLET extends them), each u runs from X along the side that was
;; clicked, and half-angle is half the turn between them -- the one
;; number the whole fillet is built from.  nil when there is no corner:
;; parallel lines, the same line twice, or two legs so nearly straight
;; through that no arc could join them.
(defun hn:corner (e1 pk1 e2 pk2 / a b x l1 l2 th)
  (setq a (hn:ends e1)
        b (hn:ends e2)
        x (inters (car a) (cadr a) (car b) (cadr b) nil))
  (if x
    (progn
      (setq x  (cal:2d x)
            l1 (hn:leg e1 x pk1)
            l2 (hn:leg e2 x pk2))
      (if (and l1 l2)
        (progn
          (setq th (abs (cal:signed-dang (angle '(0.0 0.0) (car l1))
                                        (angle '(0.0 0.0) (car l2)))))
          (if (and (> th hn:*minang*) (< th (- pi hn:*minang*)))
            (list x (car l1) (cadr l1) (car l2) (cadr l2) (/ th 2.0))))))))

;; how far back from the corner a fillet of radius R starts
(defun hn:tanlen (half r) (/ r (cal:tan half)))

;; The biggest radius this corner can take: the tangent point has to
;; land on both legs, and hn:*fit* keeps it clear of the far end so a
;; fillet never eats a leg whole.
(defun hn:rmax (geo)
  (* hn:*fit* (min (caddr geo) (nth 4 geo)) (cal:tan (nth 5 geo))))

;; centre and the two tangent points of the fillet arc of radius R
(defun hn:arcpts (geo r / x u1 u2 half tl)
  (setq x    (car geo)
        u1   (cadr geo)
        u2   (cadddr geo)
        half (nth 5 geo)
        tl   (hn:tanlen half r))
  (list (cal:v+ x (cal:v* (cal:unit (cal:v+ u1 u2)) (/ r (sin half))))
        (cal:v+ x (cal:v* u1 tl))
        (cal:v+ x (cal:v* u2 tl))))

;; EVERY radius this corner takes, ascending: hn:*first* up in
;; hn:*step*s, with hn:*extras* merged in wherever they land.  vl-sort
;; drops a duplicate, so an extra that is already on the series (a
;; re-tuned hn:*first*) is not offered twice.
(defun hn:fitting (rmax / r out)
  (setq r hn:*first*)
  (while (<= r rmax)
    (setq out (cons r out)
          r   (+ r hn:*step*)))
  (foreach r hn:*extras*
    (if (and (> r 0.0) (<= r rmax)) (setq out (cons r out))))
  (if out (vl-sort out '<)))

;; the ones actually drawn: the first hn:*maxshown* of them
(defun hn:candidates (rmax / all r out n)
  (setq all (hn:fitting rmax)
        n   0)
  (foreach r all
    (if (or (null hn:*maxshown*) (< n hn:*maxshown*))
      (setq out (cons r out)
            n   (1+ n))))
  (reverse out))

;; how many would have fitted if nothing capped the list -- what the
;; cap hid has to be said out loud, or 10 previews read as "that is all
;; this corner takes"
(defun hn:howmany (rmax) (length (hn:fitting rmax)))

;; The smallest radius anything would offer, extras included.  A corner
;; under it is the one the routine has nothing to draw for, and since
;; hn:*extras* holds a 3 that is no longer the same number as
;; hn:*first*.
(defun hn:smallest ( / m r)
  (setq m hn:*first*)
  (foreach r hn:*extras* (if (and (> r 0.0) (< r m)) (setq m r)))
  m)

;;; -------------------- the honed range -----------------------------

;; How many half-inch previews the range LO..HI comes to, BOTH ENDS
;; INCLUDED -- 12 to 18 is thirteen of them, not twelve.  The epsilon is
;; the difference between 12 steps and 11.99999999 of them: (hi - lo)
;; and hn:*fine* are both worked out in floating point, and a range that
;; came up one short would drop the radius the whole thing was honing
;; towards.
(defun hn:howfine (lo hi)
  (1+ (fix (+ 1e-6 (/ (- hi lo) hn:*fine*)))))

;; That range as a list, ascending, both ends included.  Counting up in
;; whole steps from LO rather than adding hn:*fine* to a running total
;; keeps the last one exactly HI: an accumulated 0.5 twelve times over
;; is not the same number as 12 halves.
(defun hn:finesteps (lo hi / n i out)
  (setq n (hn:howfine lo hi)
        i 0)
  (while (< i n)
    (setq out (cons (+ lo (* (float i) hn:*fine*)) out)
          i   (1+ i)))
  (reverse out))

;;; -------------------- previews ------------------------------------

;; Remember what was drawn: everything goes on the erase list, and an
;; arc also goes on the list a click is looked up in.
(defun hn:mark (en r)
  (if en
    (progn
      (setq hn:*preview* (cons en hn:*preview*))
      (if r (setq hn:*picks* (cons (cons en r) hn:*picks*)))))
  en)

;; the radius a preview arc stands for, nil for anything else in the
;; drawing
(defun hn:radof (en / p)
  (setq p (assoc en hn:*picks*))
  (if p (cdr p)))

;; Take every preview back out of the drawing.  Called on the way out
;; of the command however it ends -- a preview left behind would be
;; read as drawn work by every other tool in the toolset.
(defun hn:clear ( / e)
  (foreach e hn:*preview* (if (and e (entget e)) (entdel e)))
  (setq hn:*preview* nil
        hn:*picks*   nil))

;; The colour groups every preview entity carries: its own shade as a
;; true colour, and the transparency if there is one.  Kept in one
;; place so an arc and its label cannot end up different colours.
(defun hn:colgroups (col / out tr)
  (setq tr (hn:transval))
  (if col (setq out (list (cons 420 (hn:truecol col)))))
  (if tr (setq out (append out (list (cons 440 tr)))))
  out)

;; One preview arc in COL, drawn the short way round between its two
;; tangent points (a fillet arc is always less than a half circle).
;; DASH draws it in hn:*ltype* rather than solid -- what marks out a
;; radius that is not on the 6" series.
(defun hn:draw-arc (c r p1 p2 col dash / a1 a2 dxf)
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
                    (cons 8 hn:*layer*) (cons 62 hn:*color*)
                    (cons 6 (if dash (hn:ensure-ltype) "Continuous")))
              (if (and dash hn:*ltscale*) (list (cons 48 hn:*ltscale*)))
              (hn:colgroups col)
              (list '(100 . "AcDbCircle")
                    (list 10 (car c) (cadr c) 0.0)
                    (cons 40 r)
                    '(100 . "AcDbArc")
                    (cons 50 a1) (cons 51 a2))))
  (if (entmake dxf) (entlast)))

;; the radius, lettered beside a preview in that preview's own shade.
;; Middle-centre justified, so the text sits on the point it is given
;; whatever it says.
(defun hn:draw-label (p str col / h dxf)
  (setq h   (if hn:*txthgt* hn:*txthgt* 6.0)
        dxf (append
              (list '(0 . "TEXT") '(100 . "AcDbEntity")
                    (cons 8 hn:*layer*) (cons 62 hn:*color*))
              (hn:colgroups col)              ; entity section, as above
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
;; two together are what stops R13 landing on R13.5.
(defun hn:labelpt (anchor c i / h)
  (setq h (if hn:*txthgt* hn:*txthgt* 6.0))
  (cal:v+ anchor
         (cal:v* (cal:unit (cal:v- anchor c))
                (* h (+ 0.9 (* (if hn:*rung* hn:*rung* 0.0)
                               (float (/ i 2)))))))) ; integer divide:
                                                     ; the rung number

;; Draw the whole fan of previews, light shade to dark.  FINE says
;; which fan this is, and so which sizes come out dashed.  Labels
;; alternate between the two legs: consecutive tangent points sit one
;; step apart along one leg -- half an inch once the fan is honed --
;; which is not room enough for two labels side by side.
(defun hn:preview (geo rads fine / i n r a c t1 t2 anchor col)
  (setq i 0
        n (length rads))
  (cal:ensure-layer hn:*layer* hn:*color*)
  (foreach r rads
    (setq a   (hn:arcpts geo r)
          c   (car   a)
          t1  (cadr  a)
          t2  (caddr a)
          col (hn:shade i n))
    (hn:mark (hn:draw-arc c r t1 t2 col (hn:dashp r fine)) r)
    (if hn:*label*
      (progn
        (setq anchor (if (= 0 (rem i 2)) t1 t2))
        (hn:mark (hn:draw-label (hn:labelpt anchor c i)
                                (hn:rlabel r) col)
                 nil)))
    (setq i (1+ i))))

;;; -------------------- asking --------------------------------------

;; One entsel that insists on a LINE.  KW is the single keyword the
;; prompt offers as its way out, and it is also what Enter does -- the
;; bracket text is the keyword itself, so a click on it sends exactly
;; what is tested for, and the <default> says what an empty answer
;; means.  OTHER is the line already picked for this corner, which
;; cannot be picked twice.  Returns (ename pick-point-in-WCS), or nil
;; when the way out is taken.  Nothing has been drawn at this point, so
;; a click that lands on empty paper costing the loop is a fair trade
;; for Enter meaning what it says.
(defun hn:askline (msg kw other / sel ans typ)
  (while (not ans)
    (initget kw)
    (setq sel (entsel (strcat "\n" msg " [" kw "] <" kw ">: ")))
    (cond
      ((= (type sel) 'STR) (setq ans 'HN-NONE))
      ((null sel) (setq ans 'HN-NONE))
      ((and other (eq (car sel) other))
       (princ "\n  (that is the line you just picked -- click the OTHER leg)"))
      ((not (= "LINE" (setq typ (cdr (assoc 0 (entget (car sel)))))))
       (princ (strcat "\n  (that is a " typ " -- HONEFILLET rounds the"
                      " corner between two straight LINEs; explode a"
                      " polyline first)")))
      (t (setq ans (list (car sel) (cal:2d (trans (cadr sel) 1 0)))))))
  (if (eq ans 'HN-NONE) nil ans))

;; Which preview was clicked, as its radius.  MSG is the question --
;; this prompt is put three times in a run and means something different
;; each time.  nil when the user gives up on the corner.  It has no
;; <default>, so Enter re-asks (STANDARDS.md section 1 rule 5): the arcs
;; are thin, half an inch apart once the fan is honed, and the near-miss
;; that would throw a whole fan of them away is exactly the click this
;; prompt invites.  Cancel is in the bracket, so there is a mouse-only
;; way out that does not depend on hitting anything.
(defun hn:pickpreview (msg / sel ans r)
  (while (not ans)
    (initget "Cancel")
    (setq sel (entsel (strcat "\n" msg " [Cancel]: ")))
    (cond
      ((= (type sel) 'STR) (setq ans 'HN-NONE))
      ((null sel)
       (princ (strcat "\n  (nothing there -- click one of the green"
                      " corners, or type Cancel)")))
      ((setq r (hn:radof (car sel))) (setq ans r))
      (t (princ (strcat "\n  (that is not one of the previews -- click a"
                        " green corner)")))))
  (if (eq ans 'HN-NONE) nil ans))

;; The two previews the honed fan is drawn between, as (lo hi).  Both
;; come off the coarse fan already on screen, in either order, and the
;; pair has to pass two tests before it is one: two DIFFERENT sizes,
;; because there is no range inside a single radius, and close enough
;; together that hn:*maxfine* previews cover the ground between them.
;; A pair that fails either is said so and asked again rather than
;; quietly honed at a coarser step or truncated halfway -- both of which
;; would answer a question nobody asked.  nil when the user gives up.
(defun hn:bracket ( / a b lo hi n ans)
  (while (not ans)
    (setq a (hn:pickpreview
              "Click one of the two corners to hone between"))
    (setq b (if a (hn:pickpreview "Click the one next to it")))
    (cond
      ((or (null a) (null b)) (setq ans 'HN-NONE))
      ((equal a b 1e-9)
       (princ (strcat "\n  (that is " (hn:rlabel a) " twice -- click the"
                      " corner on the OTHER side of the size you want)")))
      ((> (setq lo (min a b)
                hi (max a b)
                n  (hn:howfine lo hi))
          hn:*maxfine*)
       (princ (strcat "\n  (" (hn:rlabel lo) " to " (hn:rlabel hi) " is "
                      (itoa n) " steps of " (hn:num hn:*fine*) "\", more"
                      " than the " (itoa hn:*maxfine*) " that can be"
                      " read at once -- pick two that sit next to each"
                      " other)")))
      (t (setq ans (list lo hi)))))
  (if (eq ans 'HN-NONE) nil ans))

;;; -------------------- cutting and dimensioning --------------------

;; Cut the corner for real.  The two picks go to FILLET exactly as the
;; user made them, so the side each line keeps is the side clicked.
;; Returns the arc FILLET made, or nil when it refused.
(defun hn:dofillet (e1 pk1 e2 pk2 r / pre new ed)
  (setq pre (entlast))
  (setvar "FILLETRAD" r)
  (command "_.FILLET" (list e1 (trans pk1 0 1)) (list e2 (trans pk2 0 1)))
  (setq new (entlast))
  (if (and new (not (eq new pre))
           (setq ed (entget new))
           (= "ARC" (cdr (assoc 0 ed))))
    new))

;; Switch to the small-dimension style for a measurement under
;; hn:*smalldim*, POOL's rule (pool:dimsbegin, POOL.LSP:370), so a
;; fillet callout matches the dims beside it.  Returns the style to go
;; back to, nil when nothing moved.
(defun hn:dimsbegin (d / od)
  (if (< d hn:*smalldim*)
    (if (tblsearch "DIMSTYLE" hn:*smallstyle*)
      (progn
        (setq od (getvar "DIMSTYLE"))
        (if (= (strcase od) (strcase hn:*smallstyle*))
          (setq od nil)                    ; already current
          (command "_.-DIMSTYLE" "_Restore" hn:*smallstyle*))
        od)
      (progn
        (if (not hn:*smallwarned*)
          (progn
            (princ (strcat "\n(no \"" hn:*smallstyle* "\" dim style in"
                           " this drawing -- the radius is dimensioned"
                           " in the current style)"))
            (setq hn:*smallwarned* t)))
        nil))))

(defun hn:dimsend (od)
  (if (and od (tblsearch "DIMSTYLE" od))
    (command "_.-DIMSTYLE" "_Restore" od)))

;; DIMSTYLE is read-only to setvar, so it goes back through a command,
;; and command-s so the same call is legal from inside *error*.
(defun hn:restyle (odim)
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
(defun hn:dimarc (arc r geo / c x out on loc od pre new)
  (setq c   (car (hn:arcpts geo r))
        x   (car geo)
        out (cal:unit (cal:v- x c)))
  (if out
    (progn
      (setq on  (cal:v+ c (cal:v* out r))
            loc (cal:v+ c (cal:v* out (+ r (if hn:*dimoff*
                                           hn:*dimoff*
                                           (max r 12.0)))))
            pre (entlast))
      (setvar "CLAYER" (cal:ensure-layer hn:*dimlayer* 2))
      (setq od (hn:dimsbegin r))
      (command "_.DIMRADIUS" (list arc (trans on 0 1))
               "_non" (trans loc 0 1))
      (hn:dimsend od)
      (setq new (entlast))
      (if (and new (not (eq new pre))) new))))

;; Re-letter a radius callout as typical.  The radius is called out
;; once and the repeats read "Typ.", the way a drafter letters it -- and
;; whether there WERE repeats is not known until the loop has run, so
;; the note is added afterwards rather than guessed at.  "<>" is
;; AutoCAD's stand-in for the measurement, so the dimension goes on
;; measuring itself.
(defun hn:typit (dim / ed)
  (if (and dim (setq ed (entget dim)))
    (progn
      (setq ed (if (assoc 1 ed)
                 (subst (cons 1 "<> Typ.") (assoc 1 ed) ed)
                 (append ed (list (cons 1 "<> Typ.")))))
      (entmod ed)
      (entupd dim))))

;; The rest of the corners, at the radius already settled on: two lines
;; each until Done.  Returns how many were cut.
(defun hn:repeat (r / n go a b geo arc)
  (setq n 0 go t)
  (while go
    (setq a (hn:askline "Select the first line of the next corner"
                        "Done" nil))
    (setq b (if a (hn:askline "Select the second line of that corner"
                              "Done" (car a))))
    (if (or (null a) (null b))
      (setq go nil)
      (progn
        (setq geo (hn:corner (car a) (cadr a) (car b) (cadr b)))
        (cond
          ((null geo)
           (princ (strcat "\n  (those two never meet at an angle --"
                          " left alone)")))
          ((< (hn:rmax geo) r)
           (princ (strcat "\n  (too short a corner for "
                          (hn:rlabel r) " -- left alone)")))
          ((setq arc (hn:dofillet (car a) (cadr a) (car b) (cadr b) r))
           (setq n (1+ n))
           (if hn:*dimrepeat* (hn:dimarc arc r geo)))
          (t (princ (strcat "\n  (AutoCAD would not fillet that corner"
                            " -- left alone)")))))))
  n)

;;; -------------------- the command ---------------------------------

(defun c:HONEFILLET ( / *error* olderr odim undo-open
                         one two geo rmax rads extra shown-extras
                         span fines r arc dim1 made)

  ;; -- restore drawing state on error / Esc.  The previews go first:
  ;;    they are entities like any other, and a run cut short partway
  ;;    would otherwise leave a fan of dashed arcs in the drawing for
  ;;    the next tool to read as work.  Then the user's settings, then
  ;;    the undo group -- left open, the next U would swallow the
  ;;    user's own work
  (setq olderr *error*)
  (defun *error* (m)
    (hn:clear)
    (cal:sysrestore)
    (hn:restyle odim)
    (if undo-open
      (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (setq *error* olderr)
    (if (and m (not (wcmatch (strcase m)
                             "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nHONEFILLET error: " m)))
    (if lzd:report (lzd:report "HONEFILLET" *honefillet-version* m))
    (princ))
  (if lzd:begin (lzd:begin "HONEFILLET" *honefillet-version*))

  (vl-load-com)
  (cal:syssave '("OSMODE" "CMDECHO" "CLAYER" "FILLETRAD" "TRIMMODE"))
  (setq odim (getvar "DIMSTYLE")
        made 0)
  (setvar "CMDECHO" 0)
  (setvar "OSMODE"  0)
  (setvar "TRIMMODE" 1)                    ; a fillet that leaves the
                                           ; old corner standing is not
                                           ; what anyone means by one

  ;; -- 1. the corner: two lines, each clicked on the side to keep
  (setq one (hn:askline "Select the first line of the corner" "Cancel" nil))
  (if one
    (setq two (hn:askline "Select the second line of the corner"
                          "Cancel" (car one))))
  (setq geo (if (and one two)
              (hn:corner (car one) (cadr one) (car two) (cadr two))))

  (cond
    ((not (and one two))
     (princ "\nHONEFILLET cancelled -- nothing drawn."))

    ((null geo)
     (princ (strcat "\nThose two lines make no corner -- they are"
                    " parallel, or they run straight through one"
                    " another.  Nothing to round.")))

    ((< (setq rmax (hn:rmax geo)) (hn:smallest))
     (princ (strcat "\nThe shorter leg of that corner only allows "
                    (hn:rlabel rmax) " -- less than the smallest"
                    " preview (" (hn:rlabel (hn:smallest)) ").  Nothing"
                    " drawn; lower hn:*first* to work at that size.")))

    ;; honing needs two sizes to hone BETWEEN, and a corner short enough
    ;; to take only one has none.  Caught here rather than at the
    ;; bracket, where the only honest answer would be to ask for a
    ;; second corner that is not on the screen and cannot be
    ((null (cdr (setq rads (hn:candidates rmax))))
     (princ (strcat "\nOnly " (hn:rlabel (car rads)) " fits that corner"
                    " -- there is no second size to hone between."
                    "  SMARTFILLET cuts it.")))

    (t
     ;; -- 2. one undo group over the previews and everything they lead
     ;;       to, so a single U undoes the lot
     ;; only when undo is recording - _Begin in a drawing with UNDO
     ;; off (bit 1 of UNDOCTL clear) errors out of the command
     (if (= 1 (logand 1 (getvar "UNDOCTL")))
       (progn
         (command "_.UNDO" "_Begin")
         (setq undo-open t)))
     ;; rads is already the candidate list -- the cond arm above tested
     ;; it for a second size and left it set
     (setq extra (- (hn:howmany rmax) (length rads)))
     (hn:preview geo rads nil)
     (princ (strcat "\n" (itoa (length rads)) " corner"
                    (if (= 1 (length rads)) "" "s")
                    " that fit, light to dark: " (hn:rlabel (car rads))
                    (if (cdr rads)
                      (strcat " to " (hn:rlabel (last rads)))
                      "")
                    " -- the sizes to hone BETWEEN, not the ones to"
                    " cut."))
     ;; which arcs are dashed is a fact about the SIZES, not about the
     ;; drawing, so it is said rather than left to be inferred from the
     ;; one preview that looks different
     (setq shown-extras (hn:shown-extras rads))
     (if shown-extras
       (princ (strcat "\nDashed: " (hn:rlist shown-extras)
                      " -- the in-between sizes, less common than a "
                      (hn:num hn:*step*) "\" step.")))
     ;; a cap that says nothing reads as "that is all this corner
     ;; takes", which is a different fact
     (if (> extra 0)
       (princ (strcat "\n" (itoa extra) " larger radi"
                      (if (= 1 extra) "us" "i") " also fit"
                      (if (= 1 extra) "s" "") " and "
                      (if (= 1 extra) "is" "are") " not shown"
                      " -- raise hn:*maxshown* to see "
                      (if (= 1 extra) "it" "them") ".")))

     ;; -- 3. the two the answer sits between, and that range redrawn at
     ;;       half inches.  Only now is there a fan to cut from: the
     ;;       coarse one was the ruler, this one is the choice
     (setq span (hn:bracket))
     (hn:clear)
     (if span
       (progn
         (setq fines (hn:finesteps (car span) (cadr span)))
         (hn:preview geo fines t)
         (princ (strcat "\n" (itoa (length fines)) " corner"
                        (if (= 1 (length fines)) "" "s") " between "
                        (hn:rlabel (car span)) " and "
                        (hn:rlabel (cadr span)) ", "
                        (hn:num hn:*fine*) "\" apart"
                        " -- the whole inches solid, the rest dashed."))))

     ;; -- 4. the one that gets cut
     (setq r (if span (hn:pickpreview "Click the rounded corner you want")))
     (hn:clear)
     (cond
       ((null r)
        (princ "\nNothing picked -- the corner is as it was."))
       ((null (setq arc (hn:dofillet (car one) (cadr one)
                                     (car two) (cadr two) r)))
        (princ (strcat "\nAutoCAD would not fillet that corner at "
                       (hn:rlabel r) " -- the lines are as they were.")))
       (t
        (setq made 1
              dim1 (hn:dimarc arc r geo))
        (princ (strcat "\n" (hn:rlabel r) " corner cut and dimensioned"
                       (if dim1 (strcat " on layer " hn:*dimlayer*) "")
                       "."))

        ;; -- 5. the same radius, for the rest of the corners
        (if (cal:askyn (strcat "Fillet other corners at "
                              (hn:rlabel r) "?")
                      "Yes" nil)
          (setq made (+ made (hn:repeat r))))
        (if (and hn:*typ* dim1 (> made 1)) (hn:typit dim1))

        (princ (strcat "\n" (itoa made) " corner"
                       (if (= 1 made) "" "s") " filleted at "
                       (hn:rlabel r)
                       (if (and hn:*typ* (> made 1) dim1)
                         " -- the one dimension now reads Typ."
                         "")
                       "."))))

     (command "_.UNDO" "_End")
     (setq undo-open nil)))

  ;; every path out drops the snapshot, the quiet ones included: a run
  ;; that found nothing to do and kept its snapshot would hand it to the
  ;; NEXT run, which would then put the user's settings back to what
  ;; they were two commands ago
  (hn:restyle odim)
  (cal:sysrestore)
  (setq *error* olderr)
  (princ))

(defun c:HONEFILLETVER ()
  (princ (strcat "\nHONEFILLET " *honefillet-version*))
  (princ))

(princ (strcat "\nHONEFILLET " *honefillet-version*
               " loaded -- type HONEFILLET, pick two lines, bracket two"
               " of the corners offered, and click one of the half-inch"
               " sizes between them."))
(princ)
