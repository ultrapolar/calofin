;;; ======================================================================
;;; POOLSIDE.lsp  --  the pool side view (longitudinal section) on its own
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  POOLSIDE     draw the side view from the floor dimensions
;;;            POOLSIDEVER  print the loaded version
;;; ======================================================================
;;;
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;
;;;  A fork of POOL.LSP's side profile, cut loose from the plan.
;;;
;;;  POOL draws that section as a by-product: the shape, the perimeter,
;;;  the corner treatments and -- out of square -- the cross dims are
;;;  all answered before it ever asks a depth, and for a Normal hopper
;;;  no section appears at all.  When the side view IS the job (a
;;;  section to hang under someone else's plan, a depth study, a floor
;;;  chain being checked against the order sheet) POOLSIDE asks for the
;;;  floor dimensions alone and draws it.
;;;
;;;  The letters are POOL's, unchanged, so a field sheet transcribes
;;;  straight across:
;;;
;;;      B    overall length, wall to wall     C    wall height
;;;      D    deep end depth                   C2   depth at the break
;;;
;;;  and the run chain, left to right, which always adds up to B:
;;;
;;;      Normal / SHallow   H  G  F  E     hopper: slope, pad, slope, flat
;;;      SLope              H  F  E        no pad -- a deep line at H
;;;      Wedge              H  F           deep line at H, floor to the wall
;;;      MOdflat            H  G  F        one pad, no shallow flat
;;;      Sport              E2 F2 G F1 E1  symmetric, a flat at each end
;;;
;;;      C  --.___                    ___.--  C           <- waterline
;;;           |   \__            ____/    |
;;;           |      \__________/         |
;;;      |-H--|---G---|----F----|----E----|
;;;
;;;  Any run may be answered NA and is read back off B; when every one
;;;  is given but they still miss B, the pad (G -- or F where the style
;;;  has no pad) absorbs the difference.  A run that resolves negative
;;;  is floored, its dimension drawn RED and a note written under the
;;;  section: the numbers come off a field sheet, and a field sheet can
;;;  disagree with itself.
;;;
;;;  A gray nominal section is on screen while the questions are asked,
;;;  with the tie being asked for lit up RED, so the letters mean
;;;  something before the pool exists.  It deletes itself once the
;;;  answers are in.
;;;
;;;  Output layers are POOL's own -- POOL (section), DIMENSION (dims),
;;;  POOL-NOTES (notes) -- so a POOLSIDE section drops under a POOL
;;;  plan without a layer to reconcile.
;;;
;;;  The grouped build: the helpers come from CALOFIN-LIB.lsp.
;;; ======================================================================

(setq *poolside-version* "v1.1")

;;; -------------------- adjustable constants ---------------------------

(setq psd:*base*       (list 0.0 0.0))  ; insertion base for this run
(setq psd:*pvents*     nil)             ; live guide entities
(setq psd:*valnotes*   nil)             ; validation problems, for the notes
(setq psd:*pv-col*     8)               ; guide outline color (dark gray)
(setq psd:*pvx-col*    7)               ; guide measuring-tie color (white)
(setq psd:*hi-col*     1)               ; highlight color (red)

;; Measurements under psd:*smalldim* are dimensioned in the drawing's
;; "STANDARD INCHES" style when it has one, exactly as POOL does, so
;; the two agree on a 19" run.  The missing-style note prints once.
(setq psd:*smalldim*    24.0)
(setq psd:*smallstyle*  "STANDARD INCHES")
(setq psd:*smallwarned* nil)
(setq psd:*dimstyle0*   nil)            ; dim style current when we started

;; The six bottom types, POOL's own keywords and capitalization -- the
;; palette and the field sheets both speak these, and a tool that spelt
;; them differently would be a second vocabulary for one question.
(setq psd:*btypes*  "Normal Sport Wedge SLope MOdflat SHallow")
(setq psd:*btshown* "Normal/Sport/Wedge/SLope/MOdflat/SHallow")

;;; -------------------- small vector helpers ---------------------------
;;; Copies of the CALOFIN-LIB originals (STANDARDS.md section 4); the
;;; grouped twin calls cal: instead.

;; local 2D point -> world 3D point (applies the insertion base)
(defun psd:wp (p)
  (list (+ (car p) (car psd:*base*))
        (+ (cadr p) (cadr psd:*base*))
        0.0))

;;; -------------------- layers and entities ----------------------------

(defun psd:line (p1 p2 lay)
  (entmake (list '(0 . "LINE")
                 (cons 8 lay)
                 (cons 10 (psd:wp p1))
                 (cons 11 (psd:wp p2)))))

(defun psd:text (pt h str lay)
  (entmake (list '(0 . "TEXT")
                 (cons 8 lay)
                 (cons 10 (psd:wp pt))
                 (cons 40 h)
                 (cons 1 str))))

(defun psd:textc (pt h str lay col)
  (entmake (list '(0 . "TEXT")
                 (cons 8 lay)
                 (cons 62 col)
                 (cons 10 (psd:wp pt))
                 (cons 40 h)
                 (cons 1 str))))

;; Override (or set) the color of an entity, refresh it, return it.
(defun psd:setcol (e col / ed old)
  (if (and e (setq ed (entget e)))
      (progn
        (setq old (assoc 62 ed))
        (if old
            (setq ed (subst (cons 62 col) old ed))
            (setq ed (append ed (list (cons 62 col)))))
        (entmod ed)
        (entupd e)))
  e)

;; Read an entity's current color (defaults to the outline gray).
(defun psd:getcol (e / ed)
  (if (and e (setq ed (entget e)) (assoc 62 ed))
      (cdr (assoc 62 ed))
      psd:*pv-col*))

;;; -------------------- guide preview ----------------------------------
;;; Everything the guide draws is tracked here, so the *error* handler
;;; can clear it after a cancel mid-prompt.

(defun psd:pvadd (e)
  (setq psd:*pvents* (cons e psd:*pvents*))
  e)

(defun psd:pvkill ( / e)
  (foreach e psd:*pvents* (if (and e (entget e)) (entdel e)))
  (setq psd:*pvents* nil))

;; Guide outline (gray) and guide measuring tie (white, so it reads
;; over the outline).
(defun psd:pvline (p1 p2)
  (psd:line p1 p2 "POOL-NOTES")
  (psd:setcol (entlast) psd:*pv-col*))

(defun psd:pvtieline (p1 p2)
  (psd:line p1 p2 "POOL-NOTES")
  (psd:setcol (entlast) psd:*pvx-col*))

;; One lettered guide tie: the measuring line and its letter, both
;; tracked and both lit while that question is being asked.  Returns
;; the highlight entry (letter ent ent).
(defun psd:tie (p q lbl th / e et)
  (setq e (psd:pvadd (psd:pvtieline p q)))
  (psd:text (cal:v+ (cal:mid p q) (list (* 0.5 th) (* 0.5 th)))
            (* 1.2 th) lbl "POOL-NOTES")
  (setq et (psd:pvadd (psd:setcol (entlast) psd:*pvx-col*)))
  (cons lbl (list e et)))

;;; -------------------- user input -------------------------------------
;;; The ask layer of STANDARDS.md section 4, under this file's prefix.

;; A plain required measurement, no guide highlight and no Back -- the
;; re-ask after a range check, where Back would step out of the check.
(defun psd:ask (msg / v)
  (cal:osup)
  (initget 7)                           ; no null, no zero, no negative
  (setq v (getdist (strcat "\n" msg ": ")))
  (cal:osdown)
  v)

;; One prompt of a sequence, with the guide entities ents lit red while
;; it is asked.  kind is REQ (required), NAX (NA accepted) or ZER (NA
;; and zero accepted).  Returns the value, nil for NA, or CAL-BACK.
(defun psd:asks (kind msg ents back / v cols kw e c)
  (setq cols (mapcar 'psd:getcol ents))
  (foreach e ents (psd:setcol e psd:*hi-col*))
  (cal:osup)
  (setq kw (cond ((eq kind 'REQ) (if back "Back Undo" nil))
                 (back "NA Back Undo")
                 (t "NA")))
  ;; REQ always rejects zero - offering Back must not loosen what
  ;; counts as a valid measurement; ZER alone admits 0
  (if kw
      (initget (if (eq kind 'ZER) 5 7) kw)
      (initget 7))
  (setq v (getdist
            (strcat "\n" msg
                    (if (eq kind 'REQ) "" " (or NA if not measured)")
                    (if back " [Back]" "")
                    ": ")))
  (cal:osdown)
  (mapcar '(lambda (e c) (psd:setcol e c)) ents cols)
  (cond ((and (= (type v) 'STR) (member v '("Back" "Undo"))) 'CAL-BACK)
        ((= (type v) 'STR) nil)               ; NA
        (t v)))

;;; -------------------- measurement sequence (Back) --------------------
;;;
;;;  Every question after the first offers Back, which re-asks the
;;;  previous one -- a typo no longer means Esc and start over.  Each
;;;  item is (key kind msg ents).

(defun psd:sq (ans key) (cdr (assoc key ans)))

(defun psd:sqput (ans key v / out p)
  (foreach p ans (if (not (eq (car p) key)) (setq out (cons p out))))
  (reverse (cons (cons key v) out)))

(defun psd:askseq (items / ans i n it v asked)
  (setq ans nil i 0 n (length items) asked nil)
  (while (< i n)
    (setq it (nth i items)
          v (psd:asks (cadr it) (caddr it) (cadddr it) (if asked t nil)))
    (if (eq v 'CAL-BACK)
        ;; Back is not offered on the first question, so there is
        ;; always somewhere to step back to
        (if asked (setq i (car asked) asked (cdr asked)))
        (setq ans (psd:sqput ans (car it) v)
              asked (cons i asked)
              i (1+ i))))
  ans)

;; The form key a letter is stored under: "E2" -> e2, "H" -> h.
(defun psd:key (s) (read (strcase s t)))

;;; -------------------- the bottom types -------------------------------
;;;
;;;  Three tables, read together, are the whole of what separates one
;;;  bottom from another: the runs it is measured by, the depth each
;;;  station between them sits at, and the nominal proportions the
;;;  guide is drawn at before any answer is in.  POOL reaches the same
;;;  six shapes by pinning G and/or E to zero inside a plan routine;
;;;  with the plan gone there is nothing left to pin, so they are
;;;  simply listed.

;; The run chain, left to right, as (letter kind what-it-measures).
;; The runs always sum to B.
(defun psd:chain (style)
  (cond
    ((= style "Wedge")
     (list (list "H" 'NAX "left end to the deep line")
           (list "F" 'NAX "deep line to the right wall")))
    ((= style "SLope")
     (list (list "H" 'NAX "left end to the deep line")
           (list "F" 'NAX "deep line to the slope break")
           (list "E" 'NAX "slope break to the right end")))
    ((= style "MOdflat")
     (list (list "H" 'NAX "left end to the flat pad")
           (list "G" 'ZER "flat pad length")
           (list "F" 'NAX "pad to the right end")))
    ((= style "Sport")
     (list (list "E2" 'NAX "left end shallow flat")
           (list "F2" 'NAX "left slope")
           (list "G"  'ZER "deep flat length, 0 = no pad (V bottom)")
           (list "F1" 'NAX "right slope")
           (list "E1" 'NAX "right end shallow flat")))
    (t                                  ; Normal and SHallow
     (list (list "H" 'NAX "left end to the deep end")
           (list "G" 'ZER "hopper length, 0 = slope bottom")
           (list "F" 'NAX "deep end to the slope break")
           (list "E" 'NAX "slope break to the right end")))))

;; The depth every station sits at, left to right.  One entry MORE than
;; the chain has runs: the two wall bottoms are stations too.
;;   "c" wall height   "d" deep depth   "c2" break depth (SHallow only)
(defun psd:depths (style)
  (cond
    ((= style "Wedge")   (list "c" "d" "c"))
    ((= style "SLope")   (list "c" "d" "c" "c"))
    ((= style "MOdflat") (list "c" "d" "d" "c"))
    ((= style "Sport")   (list "c" "c" "d" "d" "c" "c"))
    ((= style "SHallow") (list "c" "d" "d" "c2" "c"))
    (t                   (list "c" "d" "d" "c" "c"))))

;; Guide proportions of B, before a single run has been answered
;; (POOL's pool:btmnom / pool:hopsport nominals, carried across).
(defun psd:nominal (style)
  (cond
    ((= style "Wedge")   (list 0.12 0.88))
    ((= style "SLope")   (list 0.12 0.58 0.30))
    ((= style "MOdflat") (list 0.10 0.70 0.20))
    ((= style "Sport")   (list 0.12 0.20 0.30 0.26 0.12))
    (t                   (list 0.12 0.20 0.40 0.28))))

;; Which run absorbs the difference when every one was given and they
;; still miss B: the pad where the style has one, the deep-end run
;; where it does not.  (POOL's slack member, same rule.)
(defun psd:slack (chain / i k n c)
  (setq i 0 k -1 n -1)
  (foreach c chain
    (if (= (car c) "G") (setq k i))
    (if (and (< n 0) (= (car c) "F")) (setq n i))
    (setq i (1+ i)))
  (if (>= k 0) k n))

;;; -------------------- resolving the chain ----------------------------
;;; Straight ports of pool:chainfix / pool:chainval, which is what makes
;;; a POOLSIDE section and a POOL section agree on the same field sheet.

;; Remove an item by index, returning the new list.
(defun psd:setnth (lst i val / k out v)
  (setq k 0 out nil)
  (foreach v lst
    (setq out (cons (if (= k i) val v) out)
          k (1+ k)))
  (reverse out))

;; Resolve a measurement chain against the total:
;;   * NA (nil) entries take the remainder -- split evenly when there
;;     is more than one
;;   * when every value is given but the sum misses the total, the
;;     slack member at index islack absorbs the difference
(defun psd:chainfix (vals total islack / sum n share out k v)
  (setq sum 0.0 n 0)
  (foreach v vals (if v (setq sum (+ sum v)) (setq n (1+ n))))
  (setq out nil k 0)
  (if (> n 0)
      (progn
        (setq share (/ (- total sum) n))
        (foreach v vals (setq out (cons (if v v share) out))))
      (foreach v vals
        (setq out (cons (if (and (= k islack)
                                 (> (abs (- sum total)) 1.0e-6))
                            (+ v (- total sum))
                            v)
                        out)
              k (1+ k))))
  (reverse out))

;; Post-check a resolved chain: no member may be negative.  One that
;; resolved below zero is lifted to a positive floor (12", or a share
;; of the total on a short pool) and the deficit comes out of the
;; LARGEST other member.  Returns (vals fixed); fixed holds the index
;; of every member changed -- the lifted one AND its donor -- so the
;; caller can draw their dims red and say so.
(defun psd:chainval (vals total / out fixed n i j v flo need big bigi w)
  (setq n (length vals)
        flo (min 12.0 (/ (abs total) (* 4.0 n)))
        out vals fixed nil i 0)
  (while (< i n)
    (setq v (nth i out))
    (if (< v -1.0e-6)
        (progn
          (setq need (- flo v) big -1.0e30 bigi nil j 0)
          (foreach w out
            (if (and (/= j i) (> w big)) (setq big w bigi j))
            (setq j (1+ j)))
          (setq out (psd:setnth (psd:setnth out i flo) bigi (- big need))
                fixed (append fixed (list i bigi)))))
    (setq i (1+ i)))
  (list out fixed))

;; Record a validation problem: a command-line warning now, and a red
;; note under the section later.
(defun psd:valnote (msg)
  (setq psd:*valnotes* (append psd:*valnotes* (list msg)))
  (princ (strcat "\n*** " msg " ***"))
  (princ))

;; The adjusted letters as "G/F" for that note.
(defun psd:fixnames (fixed labels / out i)
  (setq out "")
  (foreach i fixed
    (setq out (strcat out (if (= out "") "" "/") (nth i labels))))
  out)

;;; -------------------- the section ------------------------------------

;; The section as ((run . depth) ...), left to right, wall bottom to
;; wall bottom: the running sum of the chain against the depth list.
(defun psd:stations (style runs wh dp c2 / out r ds v)
  (setq ds (psd:depths style)
        r 0.0
        out (list (cons 0.0 (psd:depthof (car ds) wh dp c2)))
        ds (cdr ds))
  (foreach v runs
    (setq r (+ r v)
          out (cons (cons r (psd:depthof (car ds) wh dp c2)) out)
          ds (cdr ds)))
  (reverse out))

(defun psd:depthof (k wh dp c2)
  (cond ((= k "d") dp) ((= k "c2") c2) (t wh)))

;; The x of the first station carrying depth code CODE, read through
;; any mirror.  By CODE and not by depth value: with C2 answered equal
;; to C, a search by value would land on the wall instead of the break.
(defun psd:xcode (style sta code mir / ds i k c)
  (setq ds (psd:depths style) i 0 k nil)
  (foreach c ds
    (if (and (not k) (= c code)) (setq k i))
    (setq i (1+ i)))
  (if k (car (nth (if mir (- (length sta) 1 k) k) sta))))

;; The outline: waterline across the top, a wall of height C at each
;; end, and the floor through the stations between them.  A station
;; sitting exactly on its neighbour (G answered 0 -- a slope bottom, or
;; a sport V) repeats a point, so zero-length segments are dropped
;; rather than special-cased per style.
(defun psd:secdraw (total sta lay pvflag / pts prev p)
  (setq pts (append (list (list 0.0 0.0) (list total 0.0))
                    (mapcar '(lambda (s) (list (car s) (- (cdr s))))
                            (reverse sta))
                    (list (list 0.0 0.0)))
        prev (car pts))
  (foreach p (cdr pts)
    (if (> (distance prev p) 1.0e-6)
        (if pvflag
            (psd:pvadd (psd:pvline prev p))
            (psd:line prev p lay)))
    (setq prev p)))

;; The gray nominal section plus a lettered tie per question.  Returns
;; the highlight assoc: letter -> the entities lit while it is asked.
(defun psd:guide (style total doff th / nom whn dpn c2n runs sta pv y i seg xd xb)
  (setq nom (psd:nominal style)
        whn (* 0.09 total)              ; a nominal wall height and depth:
        dpn (* 0.20 total)              ; 43" and 96" on a 40' pool
        c2n (* 0.5 (+ whn dpn))
        runs (mapcar '(lambda (f) (* f total)) nom)
        sta (psd:stations style runs whn dpn c2n))
  (psd:secdraw total sta "POOL-NOTES" t)
  ;; the run chain, on one tie line below the nominal floor
  (setq y (- (+ dpn (* 0.9 doff))) i 0 pv nil)
  (foreach seg (psd:chain style)
    (setq pv (cons (psd:tie (list (car (nth i sta)) y)
                            (list (car (nth (1+ i) sta)) y)
                            (car seg) th)
                   pv)
          i (1+ i)))
  ;; and the depths: C off the right wall, D and C2 where they fall
  (setq xd (psd:xcode style sta "d" nil)
        xb (psd:xcode style sta "c2" nil)
        pv (cons (psd:tie (list (+ total (* 0.6 doff)) 0.0)
                          (list (+ total (* 0.6 doff)) (- whn)) "C" th)
                 pv)
        pv (cons (psd:tie (list xd 0.0) (list xd (- dpn)) "D" th) pv))
  (if xb
      (setq pv (cons (psd:tie (list xb 0.0) (list xb (- c2n)) "C2" th) pv)))
  pv)

;;; -------------------- dimensions -------------------------------------

(defun psd:dimsbegin (d / odim)
  (if (< d psd:*smalldim*)
      (if (tblsearch "DIMSTYLE" psd:*smallstyle*)
          (progn
            (setq odim (getvar "DIMSTYLE"))
            ;; already current -> nothing to switch, nothing to undo
            (if (= (strcase odim) (strcase psd:*smallstyle*))
                (setq odim nil)
                (command "_.-DIMSTYLE" "_Restore" psd:*smallstyle*))
            odim)
          (progn
            (if (not psd:*smallwarned*)
                (progn
                  (princ (strcat "\n(no \"" psd:*smallstyle*
                                 "\" dim style in this drawing -- dims under "
                                 (rtos psd:*smalldim*)
                                 " drawn in the current style)"))
                  (setq psd:*smallwarned* t)))
            nil))))

(defun psd:dimsend (odim)
  (if (and odim (tblsearch "DIMSTYLE" odim))
      (command "_.-DIMSTYLE" "_Restore" odim)))

;; A horizontal / vertical dimension between two points.  The
;; orientation is STATED, not inferred from the points: a run is
;; measured between two floor points at different depths, and an
;; aligned dimension between those would read the slope instead.
(defun psd:dimh (p1 p2 pt / od)
  (setq od (psd:dimsbegin (abs (- (car p1) (car p2)))))
  (command "_.DIMLINEAR" (psd:wp p1) (psd:wp p2) "_H" (psd:wp pt))
  (psd:dimsend od))

(defun psd:dimv (p1 p2 pt / od)
  (setq od (psd:dimsbegin (abs (- (cadr p1) (cadr p2)))))
  (command "_.DIMLINEAR" (psd:wp p1) (psd:wp p2) "_V" (psd:wp pt))
  (psd:dimsend od))

;; Color the just-drawn dimension red (a measurement the validator had
;; to adjust).
(defun psd:dimred ( / e ed)
  (setq e (entlast))
  (if (and e (setq ed (entget e)))
      (entmod (if (assoc 62 ed)
                  (subst (cons 62 1) (assoc 62 ed) ed)
                  (append ed (list (cons 62 1)))))))

;;; -------------------- undo / sysvars ---------------------------------

;;; The snapshot lives in a GLOBAL and is taken only when no snapshot is
;;; already pending: if a previous run died before restoring, the stale
;;; snapshot still holds the user's TRUE settings.  Saving again there
;;; would capture the zeroed OSMODE and every later run would faithfully
;;; "restore" 0 -- the user's object snaps would look permanently wiped.

;;; -------------------- main command -----------------------------------

(defun c:POOLSIDE ( / *error* undo-open style base total doff th chain pv ans
                      wh dp c2 runs cv fixed sta segs mir sgn i s p q
                      maxd ydim odl xc xd xb y m)

  (defun *error* (msg)
    (if (and msg
             (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
        (princ (strcat "\nPOOLSIDE error: " msg)))
    ;; user settings come back FIRST so nothing below can skip them
    (cal:sysrestore)
    ;; DIMSTYLE is read-only to setvar, so it is put back the only way
    ;; it can be: dying inside a small-dim block must not leave that
    ;; style current in the user's drawing
    (psd:dimsend psd:*dimstyle0*)
    (psd:pvkill)
    (if undo-open (setq undo-open (cal:undoend)))
    (if *pop-error-mode* (*pop-error-mode*))
    (princ))

  ;; AutoCAD 2012+ requires this so *error* may call (command);
  ;; harmless no-op guard on older releases where it doesn't exist
  (if *push-error-using-command* (*push-error-using-command*))

  (cal:syssave '("OSMODE" "LUNITS" "CMDECHO" "CLAYER"))
  (setq psd:*valnotes* nil
        psd:*smallwarned* nil
        psd:*dimstyle0* (getvar "DIMSTYLE"))
  (setvar "CMDECHO" 0)
  (setq undo-open (cal:undobegin))
  ;; architectural units while prompting so every distance can be typed
  ;; as 25'6", 25'-6-1/2" or 25'6.5 as well as plain inches
  (setvar "LUNITS" 4)
  (princ "\nSide view only -- the floor dimensions, no plan.")
  (princ "\nDistances may be typed as 8'6\", 8'-6-1/2\" or 8'6.5 (plain numbers = inches).")

  (setq style (cal:askkw "Bottom type" psd:*btypes* psd:*btshown*
                         "Normal" nil))

  ;; the base point is picked with the user's own snaps still live;
  ;; only afterwards do snaps drop for the command-fed drawing work.
  ;; It is the top LEFT of the section -- the waterline at the left
  ;; wall -- so the section hangs off a known corner.
  (setq base (getpoint "\nInsertion base point (top left of the section) <0,0>: ")
        psd:*base* (if (and base (listp base))
                       (list (car base) (cadr base))
                       (list 0.0 0.0)))
  (setvar "OSMODE" 0)

  (cal:ensure-layer "POOL" 4)
  (cal:ensure-layer "DIMENSION" 2)
  (cal:ensure-layer "POOL-NOTES" 3)

  (setq total (psd:ask "B - overall length, wall to wall")
        doff  (max 12.0 (/ total 18.0))
        th    (max 3.0 (/ total 70.0))
        chain (psd:chain style)
        pv    (psd:guide style total doff th))
  (command "_.ZOOM" "_Window"
           (psd:wp (list (- doff) (- (* 0.20 total) (* 3.0 doff))))
           (psd:wp (list (+ total (* 2.0 doff)) (* 2.0 doff))))
  (princ "\nFloor dimensions -- the RED tie is the one being asked for.")
  (princ "\n(after the first answer, Back re-asks the previous one)")

  (setq ans (psd:askseq (psd:items style chain pv))
        wh  (psd:sq ans 'c)
        dp  (psd:sq ans 'd)
        c2  (if (= style "SHallow") (psd:sq ans 'c2) wh))
  ;; the two range checks POOL makes: a deep end that is not deeper
  ;; than the wall is not a deep end, and the break sits between them
  (while (<= dp wh)
    (princ (strcat "\nD must be deeper than the wall height C ("
                   (rtos wh) ") -- re-enter."))
    (setq dp (psd:ask "D - deep end depth")))
  (while (or (< c2 wh) (> c2 dp))
    (princ (strcat "\nC2 must be between C (" (rtos wh) ") and D ("
                   (rtos dp) ") -- re-enter."))
    (setq c2 (psd:ask "C2 - depth where the shallow floor meets the break")))
  (psd:pvkill)

  ;; resolve the runs against B: NA takes the remainder (split when
  ;; several), the slack member absorbs any leftover, and nothing is
  ;; allowed to come out negative
  (setq runs  (psd:chainfix (mapcar '(lambda (c) (psd:sq ans (psd:key (car c))))
                                    chain)
                            total (psd:slack chain))
        cv    (psd:chainval runs total)
        runs  (car cv)
        fixed (cadr cv))
  (if fixed
      (psd:valnote (strcat "FLOOR RUNS FAILED - "
                           (psd:fixnames fixed (mapcar 'car chain))
                           " ADJUSTED, VERIFY")))

  ;; the deep end is drawn on the left, the way the letters are
  ;; measured; mirroring swaps the section end for end and the run
  ;; dimensions with it, so the letters keep meaning what they meant
  (setq mir (cal:askyn "Put the deep end on the RIGHT?" "No" nil)
        sgn (if mir -1.0 1.0)
        sta (psd:stations style runs wh dp c2)
        segs (psd:segs chain fixed))
  (if mir
      (setq sta (reverse (mapcar '(lambda (s) (cons (- total (car s)) (cdr s)))
                                 sta))
            segs (reverse segs)))

  (psd:secdraw total sta "POOL" nil)

  (setq odl (getvar "CLAYER"))
  (setvar "CLAYER" "DIMENSION")
  (setq maxd (apply 'max (mapcar 'cdr sta))
        ydim (- (+ maxd (* 1.4 doff))))
  ;; the overall above the waterline, the run chain on one baseline
  ;; below the floor
  (psd:dimh (list 0.0 0.0) (list total 0.0)
            (list (* 0.5 total) (* 1.0 doff)))
  (setq i 0)
  (foreach s segs
    (setq p (nth i sta) q (nth (1+ i) sta))
    (if (> (abs (- (car q) (car p))) 1.0e-6)
        (progn
          (psd:dimh (list (car p) (- (cdr p))) (list (car q) (- (cdr q)))
                    (list (* 0.5 (+ (car p) (car q))) ydim))
          ;; a run the validator had to move is drawn red, so the sheet
          ;; shows which number was not the crew's
          (if (cdr s) (psd:dimred))))
    (setq i (1+ i)))
  ;; the depths: C off the shallow wall, D at the deep end, C2 at the
  ;; break when the style has one
  (setq xc (if mir 0.0 total)
        xd (psd:xcode style sta "d" mir)
        xb (psd:xcode style sta "c2" mir))
  (psd:dimv (list xc 0.0) (list xc (- wh))
            (list (+ xc (* sgn 0.8 doff)) (* -0.5 wh)))
  (psd:dimv (list xd 0.0) (list xd (- dp))
            (list (- xd (* sgn 0.5 doff)) (* -0.5 dp)))
  (if xb
      (psd:dimv (list xb 0.0) (list xb (- c2))
                (list (+ xb (* sgn 0.3 doff)) (* -0.5 c2))))
  (setvar "CLAYER" odl)

  ;; whatever had to be adjusted, in red under the section
  (setq y (- ydim (* 1.8 doff)))
  (foreach m psd:*valnotes*
    (psd:textc (list 0.0 y) (* 1.2 th) m "POOL-NOTES" 1)
    (setq y (- y (* 2.0 th))))

  (command "_.ZOOM" "_Window"
           (psd:wp (list (- (* 2.0 doff)) (- y (* 2.0 doff))))
           (psd:wp (list (+ total (* 3.0 doff)) (* 3.0 doff))))

  ;; the resolved chain, so what was read back off B is on the screen
  ;; as a number and not only as a dimension
  (princ (strcat "\n" style " side view -- B " (rtos total)))
  (setq i 0)
  (foreach s chain
    (princ (strcat "  " (car s) " " (rtos (nth i runs))))
    (setq i (1+ i)))
  (princ (strcat "  C " (rtos wh) "  D " (rtos dp)))
  (if (= style "SHallow") (princ (strcat "  C2 " (rtos c2))))

  (if undo-open (setq undo-open (cal:undoend)))
  (cal:sysrestore)
  (if *pop-error-mode* (*pop-error-mode*))
  (princ))

;; The question list: the run chain, then the depths.  ONE sequence, so
;; Back walks the lot -- a mistyped C steps back into the last run
;; rather than dropping the run.
(defun psd:items (style chain pv / out c)
  (foreach c chain
    (setq out (cons (list (psd:key (car c)) (cadr c)
                          (strcat (car c) " - " (caddr c))
                          (cdr (assoc (car c) pv)))
                    out)))
  (setq out (cons (list 'd 'REQ "D - deep end depth" (cdr (assoc "D" pv)))
                  (cons (list 'c 'REQ "C - wall height (shallow depth)"
                              (cdr (assoc "C" pv)))
                        out)))
  (if (= style "SHallow")
      (setq out (cons (list 'c2 'REQ
                            "C2 - depth where the shallow floor meets the break"
                            (cdr (assoc "C2" pv)))
                      out)))
  (reverse out))

;; One entry per run, in chain order: (letter . T when the validator
;; had to adjust it), so its dimension can be drawn red.
(defun psd:segs (chain fixed / out i c)
  (setq i 0 out nil)
  (foreach c chain
    (setq out (cons (cons (car c) (if (member i fixed) t nil)) out)
          i (1+ i)))
  (reverse out))

(defun c:POOLSIDEVER ()
  (princ (strcat "\nPOOLSIDE " *poolside-version*))
  (princ))

(princ (strcat "\nPOOLSIDE " *poolside-version*
               " loaded.  Type POOLSIDE to run."))
(princ)
