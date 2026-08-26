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
;;;  FILLET wants the radius BEFORE it shows anything, so the answer is
;;;  guessed, looked at, undone, and guessed again.  This turns that
;;;  round.  Pick the two lines and every radius that actually fits the
;;;  corner is drawn dashed, all at once, in 6-inch steps; click the one
;;;  that looks right and that is the corner you get.
;;;
;;;    1. Select the two lines that make the corner.  Click each one on
;;;       the side you want KEPT -- exactly how FILLET reads a pick:
;;;       what lies beyond the corner is trimmed away.
;;;    2. Every radius from 6 up, in 6s, that leaves both legs something
;;;       to stand on is drawn as a dashed arc labelled R6, R12, R18 ...
;;;       (at most sf:*maxshown* of them; when more fit, the routine
;;;       says how many it left out rather than silently stopping).
;;;    3. Click the arc you want.  The previews go, the corner is
;;;       filleted for real at that radius, and the arc gets its radius
;;;       dimension -- the number the shop needs, not just the shape.
;;;    4. It then offers the SAME radius for the rest of the corners:
;;;       two lines per corner until Done.  As soon as one repeat is
;;;       cut, the single dimension becomes "R12 Typ.", which is how the
;;;       radius would be lettered by hand.
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
;;;    sf:*maxshown*   most previews drawn at once        (8)
;;;    sf:*fit*        fraction of a leg a fillet may eat (0.98)
;;;    sf:*layer*      layer the previews are drawn on
;;;    sf:*color*      their colour
;;;    sf:*ltype*      their linetype, created if missing ("DASHED")
;;;    sf:*ltscale*    per-arc linetype scale, nil = the drawing's
;;;    sf:*label*      T to letter each preview R6, R12 ...
;;;    sf:*txthgt*     height of those labels
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
;;;      A corner too short for even R6 is reported, not filleted.
;;;    * The preview arcs are real entities on their own layer, erased
;;;      on the way out -- on a clean finish, on Esc, and on an error.
;;;      The empty layer is left behind; deleting it is a PURGE away.
;;;    * OSMODE, CMDECHO, CLAYER, FILLETRAD, TRIMMODE and the current
;;;      dimension style are all put back the way they were.
;;; ======================================================================

(setq *smartfillet-version* "v1.0")  ; announced on load; release_lisp.py
                                     ; reads this banner and stamps the
                                     ; dated twin in releases/ from it

;;; -------------------- tunables ------------------------------------

(setq sf:*first*      6.0)   ; the smallest radius offered, and the step
(setq sf:*step*       6.0)   ; between the ones after it -- 6" of radius
                             ; is the smallest difference that reads on
                             ; a pool plan
(setq sf:*maxshown*   8)     ; how many previews may be on screen at
                             ; once; nil = every radius that fits, which
                             ; on a long wall is a great many
(setq sf:*fit*        0.98)  ; how much of the shorter leg a fillet may
                             ; use up: 1.0 would put the tangent point
                             ; exactly on the far end and leave a
                             ; zero-length line behind
(setq sf:*layer*      "SMART FILLET PREVIEW")
(setq sf:*color*      3)     ; green, so a preview reads as a preview
                             ; whatever the layer was set to by hand
(setq sf:*ltype*      "DASHED")
(setq sf:*ltscale*    0.25)  ; the stock DASHED pattern is 18 units
                             ; long, so a 6" fillet arc (9 units of it)
                             ; would come out as one unbroken dash; a
                             ; quarter-scale pattern puts real gaps in
                             ; even the smallest preview.  nil = leave
                             ; the arcs at the drawing's own LTSCALE
(setq sf:*label*      t)
(setq sf:*txthgt*     6.0)
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

(setq sf:*sysold*     nil)   ; sysvar snapshot, live only mid-run
(setq sf:*preview*    nil)   ; every entity drawn as a preview
(setq sf:*picks*      nil)   ; (preview-arc . radius), what a click means
(setq sf:*smallwarned* nil)  ; the missing-style note is said once

;;; -------------------- shared helpers ------------------------------
;;; The generic CALOFIN-LIB helpers this tool leans on.  Here they are
;;; copies under this file's own prefix, so it loads alone with
;;; APPLOAD; in the shared/ twin they are gone and every call site
;;; reads cal: instead.  Bodies identical to the library's.

;; Keyword question.  kws is the initget string, shown the bracketed
;; list, dflt the Enter answer (nil = an answer is required).  Returns
;; the keyword or SF-BACK.  Undo is a hidden synonym for Back.
(defun sf:askkw (msg kws shown dflt back / v)
  (initget (if dflt 0 (if back 0 1))
           (if back (strcat kws " Back Undo") kws))
  (setq v (getkword (strcat "\n" msg " [" shown
                            (if back "/Back" "") "]"
                            (if dflt (strcat " <" dflt ">") "") ": ")))
  (cond ((member v '("Back" "Undo")) 'SF-BACK)
        ((null v) (if dflt dflt (sf:askkw msg kws shown dflt back)))
        (t v)))

;; Yes/No that can be backed out of.  Returns T, nil or SF-BACK.
(defun sf:askyn (msg dflt back / v)
  (setq v (sf:askkw msg "Yes No" "Yes/No" dflt back))
  (if (eq v 'SF-BACK) v (= v "Yes")))

;; System-variable snapshot in a GLOBAL, taken only when none is
;; pending, so a run that died before restoring cannot make the next
;; run "restore" its zeroed settings.  OSMODE first in the list.
(defun sf:syssave (vars / v)
  (if (not sf:*sysold*)
      (foreach v vars
        (if (/= nil (getvar v))
            (setq sf:*sysold*
                  (append sf:*sysold* (list (cons v (getvar v)))))))))

(defun sf:sysrestore ( / p)
  (foreach p sf:*sysold* (setvar (car p) (cdr p)))
  (setq sf:*sysold* nil))

;; Create the output layer, or - when it already exists - make sure it
;; is on, thawed and unlocked.  Returns the layer name.
(defun sf:ensure-layer (name color / rec ed flags col fixed)
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

;; 2-D vector helpers; inputs may be 2- or 3-element (the Z is dropped)
(defun sf:2d (p) (list (car p) (cadr p)))
(defun sf:dist (a b) (distance (sf:2d a) (sf:2d b)))
(defun sf:v- (a b) (mapcar '- (sf:2d a) (sf:2d b)))
(defun sf:v+ (a b) (mapcar '+ (sf:2d a) (sf:2d b)))
(defun sf:v* (v s) (list (* (car v) s) (* (cadr v) s)))
(defun sf:dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))
(defun sf:vlen (v) (sqrt (sf:dot v v)))

;; v scaled to length 1; nil for a (near-)zero vector.
(defun sf:unit (v / l)
  (setq v (sf:2d v)
        l (sf:vlen v))
  (if (> l 1e-12) (sf:v* v (/ 1.0 l))))

;; normalize an angle into [0, 2pi)
(defun sf:angnorm (a)
  (while (< a 0.0) (setq a (+ a pi pi)))
  (while (>= a (+ pi pi)) (setq a (- a pi pi)))
  a)

;; smallest signed angular difference (to - from), in (-pi, pi]
(defun sf:signed-dang (from to / d)
  (setq d (sf:angnorm (- to from)))
  (if (> d pi) (- d (* 2.0 pi)) d))

;; Tangent with the angle clamped just short of +/-90 degrees, so a
;; degenerate half-turn yields a huge but finite number instead of
;; dividing by zero.
(defun sf:tan (x)
  (cond ((> x  1.5697) (setq x  1.5697))    ; 89.94 deg
        ((< x -1.5697) (setq x -1.5697)))
  (/ (sin x) (cos x)))

;;; -------------------- small local helpers -------------------------

;; A number without AutoLISP's trailing zeros: 12, not 12.000000.
(defun sf:num (x)
  (cond ((null x) "?")
        ((= x (fix x)) (rtos x 2 0))
        (t (rtos x 2 2))))

;; "R12", the way a radius is lettered
(defun sf:rlabel (r) (strcat "R" (sf:num r)))

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
  (list (sf:2d (trans (cdr (assoc 10 ed)) en 0))
        (sf:2d (trans (cdr (assoc 11 ed)) en 0))))

;;; -------------------- the corner ----------------------------------

;; One leg of the corner: which way the line runs from the crossing
;; point X on the side that was CLICKED -- the side FILLET keeps -- and
;; how far it reaches that way.  Returns (unit-direction reach), or nil
;; when the line has no length.  The pick decides the direction and the
;; far endpoint decides the reach, so a line whose crossing point lies
;; off its own end (the case FILLET handles by extending it) is
;; measured the same way as one the corner sits inside.
(defun sf:leg (en x pk / ends a b d s u av)
  (setq ends (sf:ends en)
        a    (car  ends)
        b    (cadr ends)
        d    (sf:unit (sf:v- b a)))
  (if d
    (progn
      (setq s (sf:dot d (sf:v- pk x)))
      ;; clicked on the corner itself, where neither side is nearer:
      ;; take the end with more line behind it, the only one a fillet
      ;; could stand on
      (if (< (abs s) 1e-6)
        (setq s (if (>= (sf:dist a x) (sf:dist b x))
                  (sf:dot d (sf:v- a x))
                  (sf:dot d (sf:v- b x)))))
      (setq u  (if (< s 0.0) (sf:v* d -1.0) d)
            av (max (sf:dot u (sf:v- a x)) (sf:dot u (sf:v- b x))))
      (if (> av 1e-9) (list u av)))))

;; Everything about the corner two picked lines make, worked out once:
;;   (X u1 reach1 u2 reach2 half-angle)
;; X is where the two lines cross (extended if they have to be, as
;; FILLET extends them), each u runs from X along the side that was
;; clicked, and half-angle is half the turn between them -- the one
;; number the whole fillet is built from.  nil when there is no corner:
;; parallel lines, the same line twice, or two legs so nearly straight
;; through that no arc could join them.
(defun sf:corner (e1 pk1 e2 pk2 / a b x l1 l2 th)
  (setq a (sf:ends e1)
        b (sf:ends e2)
        x (inters (car a) (cadr a) (car b) (cadr b) nil))
  (if x
    (progn
      (setq x  (sf:2d x)
            l1 (sf:leg e1 x pk1)
            l2 (sf:leg e2 x pk2))
      (if (and l1 l2)
        (progn
          (setq th (abs (sf:signed-dang (angle '(0.0 0.0) (car l1))
                                        (angle '(0.0 0.0) (car l2)))))
          (if (and (> th sf:*minang*) (< th (- pi sf:*minang*)))
            (list x (car l1) (cadr l1) (car l2) (cadr l2) (/ th 2.0))))))))

;; how far back from the corner a fillet of radius R starts
(defun sf:tanlen (half r) (/ r (sf:tan half)))

;; The biggest radius this corner can take: the tangent point has to
;; land on both legs, and sf:*fit* keeps it clear of the far end so a
;; fillet never eats a leg whole.
(defun sf:rmax (geo)
  (* sf:*fit* (min (caddr geo) (nth 4 geo)) (sf:tan (nth 5 geo))))

;; centre and the two tangent points of the fillet arc of radius R
(defun sf:arcpts (geo r / x u1 u2 half tl)
  (setq x    (car geo)
        u1   (cadr geo)
        u2   (cadddr geo)
        half (nth 5 geo)
        tl   (sf:tanlen half r))
  (list (sf:v+ x (sf:v* (sf:unit (sf:v+ u1 u2)) (/ r (sin half))))
        (sf:v+ x (sf:v* u1 tl))
        (sf:v+ x (sf:v* u2 tl))))

;; every radius that fits, from sf:*first* up in sf:*step*s, capped at
;; sf:*maxshown*
(defun sf:candidates (rmax / r out)
  (setq r sf:*first*)
  (while (and (<= r rmax)
              (or (null sf:*maxshown*) (< (length out) sf:*maxshown*)))
    (setq out (cons r out)
          r   (+ r sf:*step*)))
  (reverse out))

;; how many would have fitted if nothing capped the list -- what the
;; cap hid has to be said out loud, or 8 previews read as "that is all
;; this corner takes"
(defun sf:howmany (rmax / r n)
  (setq r sf:*first* n 0)
  (while (<= r rmax) (setq n (1+ n) r (+ r sf:*step*)))
  n)

;;; -------------------- previews ------------------------------------

;; Remember what was drawn: everything goes on the erase list, and an
;; arc also goes on the list a click is looked up in.
(defun sf:mark (en r)
  (if en
    (progn
      (setq sf:*preview* (cons en sf:*preview*))
      (if r (setq sf:*picks* (cons (cons en r) sf:*picks*)))))
  en)

;; the radius a preview arc stands for, nil for anything else in the
;; drawing
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

;; one dashed preview arc, drawn the short way round between its two
;; tangent points (a fillet arc is always less than a half circle)
(defun sf:draw-arc (c r p1 p2 / a1 a2 dxf)
  (setq a1 (angle c p1)
        a2 (angle c p2))
  (if (> (sf:angnorm (- a2 a1)) pi)
    (setq a1 (angle c p2)
          a2 (angle c p1)))
  (setq dxf (list '(0 . "ARC") '(100 . "AcDbEntity")
                  (cons 8 sf:*layer*) (cons 62 sf:*color*)
                  (cons 6 (sf:ensure-ltype))
                  '(100 . "AcDbCircle")
                  (list 10 (car c) (cadr c) 0.0)
                  (cons 40 r)
                  '(100 . "AcDbArc")
                  (cons 50 a1) (cons 51 a2)))
  (if sf:*ltscale* (setq dxf (append dxf (list (cons 48 sf:*ltscale*)))))
  (if (entmake dxf) (entlast)))

;; the radius, lettered beside a preview.  Middle-centre justified, so
;; the text sits on the point it is given whatever it says.
(defun sf:draw-label (p str / h)
  (setq h (if sf:*txthgt* sf:*txthgt* 6.0))
  (if (entmake (list '(0 . "TEXT") '(100 . "AcDbEntity")
                     (cons 8 sf:*layer*) (cons 62 sf:*color*)
                     '(100 . "AcDbText")
                     (list 10 (car p) (cadr p) 0.0)
                     (cons 40 h) (cons 1 str)
                     '(72 . 1)                       ; centred across
                     (list 11 (car p) (cadr p) 0.0)
                     '(100 . "AcDbText")
                     '(73 . 2)))                     ; and down
    (entlast)))

;; Draw the whole fan of previews.  Labels alternate between the two
;; legs: consecutive tangent points sit one step apart along one leg,
;; which is not room enough for two labels side by side.
(defun sf:preview (geo rads / i r a c t1 t2 anchor)
  (setq i 0)
  (sf:ensure-layer sf:*layer* sf:*color*)
  (foreach r rads
    (setq a  (sf:arcpts geo r)
          c  (car   a)
          t1 (cadr  a)
          t2 (caddr a))
    (sf:mark (sf:draw-arc c r t1 t2) r)
    (if sf:*label*
      (progn
        (setq anchor (if (= 0 (rem i 2)) t1 t2))
        ;; pushed straight off the arc, away from its centre, so the
        ;; label never lands on the line it belongs to
        (sf:mark (sf:draw-label
                   (sf:v+ anchor
                          (sf:v* (sf:unit (sf:v- anchor c))
                                 (* 0.9 (if sf:*txthgt* sf:*txthgt* 6.0))))
                   (sf:rlabel r))
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
(defun sf:askline (msg kw other / sel ans typ)
  (while (not ans)
    (initget kw)
    (setq sel (entsel (strcat "\n" msg " [" kw "] <" kw ">: ")))
    (cond
      ((= (type sel) 'STR) (setq ans 'SF-NONE))
      ((null sel) (setq ans 'SF-NONE))
      ((and other (eq (car sel) other))
       (princ "\n  (that is the line you just picked -- click the OTHER leg)"))
      ((not (= "LINE" (setq typ (cdr (assoc 0 (entget (car sel)))))))
       (princ (strcat "\n  (that is a " typ " -- SMARTFILLET rounds the"
                      " corner between two straight LINEs; explode a"
                      " polyline first)")))
      (t (setq ans (list (car sel) (sf:2d (trans (cadr sel) 1 0)))))))
  (if (eq ans 'SF-NONE) nil ans))

;; Which preview was clicked, as its radius.  nil when the user gives
;; up on the corner.  This one has no <default>, so Enter re-asks
;; (STANDARDS.md section 1 rule 5): the arcs are thin and the near-miss
;; that would throw a whole fan of them away is exactly the click this
;; prompt invites.  Cancel is in the bracket, so there is a mouse-only
;; way out that does not depend on hitting anything.
(defun sf:pickpreview ( / sel ans r)
  (while (not ans)
    (initget "Cancel")
    (setq sel (entsel "\nClick the rounded corner you want [Cancel]: "))
    (cond
      ((= (type sel) 'STR) (setq ans 'SF-NONE))
      ((null sel)
       (princ (strcat "\n  (nothing there -- click one of the dashed"
                      " corners, or type Cancel)")))
      ((setq r (sf:radof (car sel))) (setq ans r))
      (t (princ (strcat "\n  (that is not one of the previews -- click a"
                        " dashed corner)")))))
  (if (eq ans 'SF-NONE) nil ans))

;;; -------------------- cutting and dimensioning --------------------

;; Cut the corner for real.  The two picks go to FILLET exactly as the
;; user made them, so the side each line keeps is the side clicked.
;; Returns the arc FILLET made, or nil when it refused.
(defun sf:dofillet (e1 pk1 e2 pk2 r / pre new ed)
  (setq pre (entlast))
  (setvar "FILLETRAD" r)
  (command "_.FILLET" (list e1 (trans pk1 0 1)) (list e2 (trans pk2 0 1)))
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
        out (sf:unit (sf:v- x c)))
  (if out
    (progn
      (setq on  (sf:v+ c (sf:v* out r))
            loc (sf:v+ c (sf:v* out (+ r (if sf:*dimoff*
                                           sf:*dimoff*
                                           (max r 12.0)))))
            pre (entlast))
      (setvar "CLAYER" (sf:ensure-layer sf:*dimlayer* 2))
      (setq od (sf:dimsbegin r))
      (command "_.DIMRADIUS" (list arc (trans on 0 1))
               "_non" (trans loc 0 1))
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
                 (subst (cons 1 "<> Typ.") (assoc 1 ed) ed)
                 (append ed (list (cons 1 "<> Typ.")))))
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

(defun c:SMARTFILLET ( / *error* olderr odim undo-open
                         one two geo rmax rads extra r arc dim1 made)

  ;; -- restore drawing state on error / Esc.  The previews go first:
  ;;    they are entities like any other, and a run cut short partway
  ;;    would otherwise leave a fan of dashed arcs in the drawing for
  ;;    the next tool to read as work.  Then the user's settings, then
  ;;    the undo group -- left open, the next U would swallow the
  ;;    user's own work
  (setq olderr *error*)
  (defun *error* (m)
    (sf:clear)
    (sf:sysrestore)
    (sf:restyle odim)
    (if undo-open
      (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (setq *error* olderr)
    (if (and m (not (wcmatch (strcase m)
                             "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nSMARTFILLET error: " m)))
    (princ))

  (vl-load-com)
  (sf:syssave '("OSMODE" "CMDECHO" "CLAYER" "FILLETRAD" "TRIMMODE"))
  (setq odim (getvar "DIMSTYLE")
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

    ((< (setq rmax (sf:rmax geo)) sf:*first*)
     (princ (strcat "\nThe shorter leg of that corner only allows "
                    (sf:rlabel rmax) " -- less than the smallest"
                    " preview (" (sf:rlabel sf:*first*) ").  Nothing"
                    " drawn; lower sf:*first* to work at that size.")))

    (t
     ;; -- 2. one undo group over the previews and everything they lead
     ;;       to, so a single U undoes the lot
     (command "_.UNDO" "_Begin")
     (setq undo-open t
           rads      (sf:candidates rmax)
           extra     (- (sf:howmany rmax) (length rads)))
     (sf:preview geo rads)
     (princ (strcat "\n" (itoa (length rads)) " corner"
                    (if (= 1 (length rads)) "" "s")
                    " that fit, dashed: " (sf:rlabel (car rads))
                    (if (cdr rads)
                      (strcat " to " (sf:rlabel (last rads)))
                      "")
                    "."))
     ;; a cap that says nothing reads as "that is all this corner
     ;; takes", which is a different fact
     (if (> extra 0)
       (princ (strcat "\n" (itoa extra) " larger radi"
                      (if (= 1 extra) "us" "i") " also fit"
                      (if (= 1 extra) "s" "") " and "
                      (if (= 1 extra) "is" "are") " not shown"
                      " -- raise sf:*maxshown* to see "
                      (if (= 1 extra) "it" "them") ".")))

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
        (if (sf:askyn (strcat "Fillet other corners at "
                              (sf:rlabel r) "?")
                      "Yes" nil)
          (setq made (+ made (sf:repeat r))))
        (if (and sf:*typ* dim1 (> made 1)) (sf:typit dim1))

        (princ (strcat "\n" (itoa made) " corner"
                       (if (= 1 made) "" "s") " filleted at "
                       (sf:rlabel r)
                       (if (and sf:*typ* (> made 1) dim1)
                         " -- the one dimension now reads Typ."
                         "")
                       "."))))

     (command "_.UNDO" "_End")
     (setq undo-open nil)))

  ;; every path out drops the snapshot, the quiet ones included: a run
  ;; that found nothing to do and kept its snapshot would hand it to the
  ;; NEXT run, which would then put the user's settings back to what
  ;; they were two commands ago
  (sf:restyle odim)
  (sf:sysrestore)
  (setq *error* olderr)
  (princ))

(defun c:SMARTFILLETVER ()
  (princ (strcat "\nSMARTFILLET " *smartfillet-version*))
  (princ))

(princ (strcat "\nSMARTFILLET " *smartfillet-version*
               " loaded -- type SMARTFILLET, pick two lines, and click"
               " the rounded corner you want."))
(princ)
