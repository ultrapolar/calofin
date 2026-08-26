;;; ======================================================================
;;; CUSTBLOCK.lsp  --  draw a custom block in pictorial view from its
;;;                    length, width and height, dimensioned
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  CUSTBLOCK      ask L/W/H and draw the block
;;;            CUSTBLOCKVER   print the loaded version
;;;
;;;  Three questions and a base point, and the block is on the sheet:
;;;
;;;    1. Block length   -- the long axis, drawn receding back-right
;;;    2. Block width    -- across the front face
;;;    3. Block height   -- up the front face
;;;    4. Insertion base point (Enter = 0,0) -- the FRONT BOTTOM LEFT
;;;       corner of the block
;;;
;;;  What is drawn (the 84 x 36 x 4 block of the sample sheet, if those
;;;  are the three answers):
;;;
;;;      * nine lines on layer "COVER" -- the front face, the top face
;;;        and the right-hand face of the box.  The three hidden edges
;;;        (the bottom-left receding edge, the bottom and the left edge
;;;        of the back face) are NOT drawn, which is what makes it read
;;;        as a solid block rather than a wire cage.
;;;      * the length receding at 45 degrees, at TRUE length -- it is a
;;;        pictorial, not an isometric projection, so the dimension on
;;;        that edge reads the number that was typed.
;;;      * three dimensions on layer "DIMENSION" in the "STANDARD
;;;        INCHES" style: the length aligned along the top-left
;;;        receding edge, the height up the left of the front face, the
;;;        width along under it.  Text centred, dimension lines pushed
;;;        cbk:*dimoff* clear of the block.
;;;
;;;  The whole run is one undo group: a single U takes the block and
;;;  its dimensions away together.
;;;
;;;  Usage
;;;    Command: CUSTBLOCK
;;;    Command: CUSTBLOCKVER     prints the version
;;;
;;;  Tunables (setq them after loading if a drawing needs different
;;;  names, e.g. in a startup file):
;;;    cbk:*layer*     layer the block lines go on   ("COVER")
;;;    cbk:*laycolor*  colour that layer is created with, when the
;;;                    drawing has no such layer yet (7)
;;;    cbk:*dimlayer*  layer the dimensions go on    ("DIMENSION")
;;;    cbk:*dimcolor*  colour IT is created with     (141)
;;;    cbk:*style*     dimension style to use        ("STANDARD INCHES")
;;;    cbk:*dimoff*    how far the dimension lines stand off the block,
;;;                    drawing units (12.0 = a foot in an inch drawing)
;;;
;;;  Notes
;;;    * Back (or Undo, or B) at any question after the first re-asks
;;;      the one before it.  Nothing is drawn until all four answers
;;;      are in, so backing out costs nothing.
;;;    * Length, width and height are all required and all must be
;;;      positive -- a zero-thickness block has no pictorial to draw.
;;;      Either type the number or pick the distance in the drawing;
;;;      your own object snaps stay live for that, and for the base
;;;      point.
;;;    * The layers are created when the drawing lacks them, and
;;;      thawed / unlocked / switched back on when they are there but
;;;      not usable -- a run onto a frozen layer would otherwise look
;;;      like the command did nothing.
;;;      A missing "STANDARD INCHES" style is NOT invented: the dims
;;;      are drawn in whatever style is current and the routine says
;;;      so, so a drawing started from the wrong template is obvious
;;;      instead of silently producing wrong-looking dims.
;;;    * The dimension style, current layer, CMDECHO and OSMODE in
;;;      force before the command are restored afterwards, on a clean
;;;      finish, an error, or Esc.
;;; ======================================================================

(setq *custblock-version* "v1.0")  ; announced on load; release_lisp.py
                                   ; reads this banner and stamps the
                                   ; dated twin in releases/ from it

(setq cbk:*layer*    "COVER")           ; the block itself
(setq cbk:*laycolor* 7)
(setq cbk:*dimlayer* "DIMENSION")       ; its dimensions
(setq cbk:*dimcolor* 141)
(setq cbk:*style*    "STANDARD INCHES")
(setq cbk:*dimoff*   12.0)              ; dim line stand-off, units
(setq cbk:*sysold*   nil)               ; sysvar snapshot, live mid-run

;;; -------------------- helpers -----------------------------------------

;; The sysvars this tool moves, saved in restore order -- OSMODE first,
;; because object snaps are the setting the user misses most if a run is
;; ever cut short partway.
(defun cbk:syssave (vars / v)
  (if (not cbk:*sysold*)
    (foreach v vars
      (if (/= nil (getvar v))
        (setq cbk:*sysold*
              (append cbk:*sysold* (list (cons v (getvar v)))))))))

(defun cbk:sysrestore ( / p)
  (foreach p cbk:*sysold* (setvar (car p) (cdr p)))
  (setq cbk:*sysold* nil))

;; Create the output layer, or - when it already exists - make sure it
;; is on, thawed and unlocked.  Without this a successful run onto a
;; frozen or switched-off layer looks like the command did nothing.
;; Returns the layer NAME in every case.
(defun cbk:ensure-layer (name color / rec ed flags col fixed)
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

;; Distance entry with the kind system of STANDARDS.md section 3.
;; Returns the number, nil for NA, or CBK-BACK.
(defun cbk:askdist (kind msg dflt back / v kw)
  ;; Undo is accepted everywhere Back is, as a hidden synonym
  (setq kw (cond ((eq kind 'REQ) (if back "Back Undo" nil))
                 (back "NA Back Undo")
                 (t "NA")))
  ;; REQ always rejects zero - offering Back must not loosen what
  ;; counts as a valid measurement; ZER alone admits 0
  (if kw
      (initget (cond ((eq kind 'ZER) 5)
                     ((and (eq kind 'SUG) dflt) 6)
                     (t 7))
               kw)
      (initget 7))
  (setq v (getdist
            (strcat "\n" msg
                    (cond ((eq kind 'REQ) "")
                          ((eq kind 'SUG)
                           (if dflt (strcat " <" (rtos dflt) "> (or NA)")
                               " (or NA)"))
                          (t " (or NA if not measured)"))
                    (if back " [Back]" "")
                    ": ")))
  (cond ((and (= (type v) 'STR) (member v '("Back" "Undo"))) 'CBK-BACK)
        ((= (type v) 'STR) nil)               ; NA
        ((and (null v) (eq kind 'SUG)) dflt)  ; Enter took the suggestion
        (t v)))

;; Where the block goes -- its front bottom left corner.  Picked with
;; the user's own object snaps still live, and backed out of like any
;; other question; nothing has been drawn at that point.  Enter takes
;; the origin.  Returns a 3-D point (the elevation is carried, so a UCS
;; with one is honoured) or CBK-BACK.
(defun cbk:askbase (back / v)
  (if back (initget "Back Undo"))
  ;; bracket before the default, the one prompt shape of STANDARDS.md
  ;; section 1 -- the wording itself is section 3's Placement question
  (setq v (getpoint (strcat "\nInsertion base point"
                            (if back " [Back]" "") " <0,0>: ")))
  (cond ((and (= (type v) 'STR) (member v '("Back" "Undo"))) 'CBK-BACK)
        ((null v) (list 0.0 0.0 0.0))
        (t (list (car v) (cadr v) (if (caddr v) (caddr v) 0.0)))))

;; A point of the block: x across the front, y up it, both measured
;; from the base point.  Every corner below is built through here, so
;; the whole block moves with one answer -- and every one of them is in
;; the CURRENT UCS, which is where the base point arrived from, so the
;; block lies flat in the coordinate system the drafter is working in.
(defun cbk:pt (base x y)
  (list (+ (car base) x) (+ (cadr base) y) (caddr base)))

;; One block edge.  entmakex rather than the LINE command: no command
;; echo, no chance of a running object snap catching an endpoint, and
;; the layer is stated outright instead of depending on CLAYER.  entmake
;; wants WORLD coordinates, so the two UCS points are translated on the
;; way in -- skip that and the block lands somewhere else entirely under
;; a rotated or shifted UCS.
(defun cbk:line (p1 p2)
  (entmakex (list '(0 . "LINE") '(100 . "AcDbEntity")
                  (cons 8 cbk:*layer*) '(100 . "AcDbLine")
                  (cons 10 (trans p1 1 0)) (cons 11 (trans p2 1 0)))))

;; restore a dimension style by name when the drawing has it;
;; returns T when the style was set
(defun cbk:setstyle (name)
  (if (and name (tblsearch "DIMSTYLE" name))
    (progn (command "_.-DIMSTYLE" "_Restore" name) t)))

;; DIMSTYLE is read-only to setvar, so it goes back through a command --
;; and only when the style really did move: a run that never found
;; "STANDARD INCHES" should not leave a pointless -DIMSTYLE Restore in
;; the drawing's command history.  command-s, so the same call is legal
;; from inside the error handler.
(defun cbk:restyle (odim)
  (if (and odim (tblsearch "DIMSTYLE" odim)
           (not (equal odim (getvar "DIMSTYLE"))))
    (vl-catch-all-apply 'command-s
                        (list "_.-DIMSTYLE" "_Restore" odim))))

;; a copy of an entget list with every entry for group CODE dropped
(defun cbk:strip (code lst / out)
  (foreach g lst (if (/= code (car g)) (setq out (cons g out))))
  (reverse out))

;; force a freshly drawn dimension onto the layer and style CUSTBLOCK
;; promises, ByLayer -- DIMLAYER, a style-owned layer or a leftover
;; per-entity override would otherwise have the last word
(defun cbk:fixdim (en havestyle / ed)
  (if (and en (setq ed (entget en))
           (= "DIMENSION" (cdr (assoc 0 ed))))
    (progn
      (setq ed (if (assoc 8 ed)
                 (subst (cons 8 cbk:*dimlayer*) (assoc 8 ed) ed)
                 (append ed (list (cons 8 cbk:*dimlayer*)))))
      (if havestyle
        (setq ed (if (assoc 3 ed)
                   (subst (cons 3 cbk:*style*) (assoc 3 ed) ed)
                   (append ed (list (cons 3 cbk:*style*))))))
      (foreach code '(62 6 370) (setq ed (cbk:strip code ed)))
      (entmod ed)
      (entupd en)
      t)))

;; Draw one dimension and hand it its layer and style.  kind is 'ALIGNED
;; for a dim that reads along its own axis (the receding length edge),
;; 'HORIZ or 'VERT for a linear one held to the horizontal or the
;; vertical -- forced, rather than left to AutoCAD to infer from where
;; the dimension line was put, so a stand-off the user has retuned
;; cannot flip a width dim into a height one.  (Spelled out, not 'H and
;; 'V: AutoLISP symbols are case-blind, so a bare 'V is the same symbol
;; as a local named v.)
(defun cbk:dim (kind p1 p2 loc havestyle / pre new)
  ;; the points go in as they were built, in the current UCS, which is
  ;; what a command reads; _non so a running object snap cannot pull an
  ;; extension line origin onto nearby geometry
  (setq pre (entlast))
  (if (eq kind 'ALIGNED)
    (command "_.DIMALIGNED" "_non" p1 "_non" p2 "_non" loc)
    (command "_.DIMLINEAR" "_non" p1 "_non" p2
             (if (eq kind 'VERT) "_V" "_H") "_non" loc))
  (setq new (entlast))
  (if (and new (not (eq new pre)))
    (progn (cbk:fixdim new havestyle) new)))

;; how the numbers read back in the closing report -- rtos in the
;; drawing's own units, so a 4'-0" block says 4'-0" on an architectural
;; sheet and 48 on a decimal one
(defun cbk:num (x) (rtos x))

;;; -------------------- the command -------------------------------------

(defun c:CUSTBLOCK ( / *error* olderr odim
                       step len wid hgt base v d
                       pa pb pc pd qb qc qd
                       havestyle undo-open off made )

  ;; -- restore drawing state on error / Esc.  The user's settings come
  ;;    back FIRST so nothing below can skip them; a dimension command
  ;;    may still be open, so AutoCAD is talked to through command-s --
  ;;    and the undo group is closed, or the next U would swallow the
  ;;    user's own work
  (setq olderr *error*)
  (defun *error* (m)
    (cbk:sysrestore)
    (cbk:restyle odim)
    (if undo-open
      (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (setq *error* olderr)
    (if (and m (not (wcmatch (strcase m)
                             "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nCUSTBLOCK error: " m)))
    (princ))

  (cbk:syssave '("OSMODE" "CMDECHO" "CLAYER"))
  (setq odim (getvar "DIMSTYLE"))

  ;; -- 1. the four answers.  Back re-asks the question before; the
  ;;       first question never offers it, and nothing is drawn until
  ;;       all four are in, so a run can be walked backwards for free
  (setq step 1)
  (while (< step 5)
    (cond
      ((= step 1)
         (setq len  (cbk:askdist 'REQ "Block length" nil nil)
               step 2))
      ((= step 2)
         (setq v (cbk:askdist 'REQ "Block width" nil T))
         (if (eq v 'CBK-BACK)
           (progn (princ "\nStepping back one dimension.")
                  (setq step 1))
           (setq wid v step 3)))
      ((= step 3)
         (setq v (cbk:askdist 'REQ "Block height" nil T))
         (if (eq v 'CBK-BACK)
           (progn (princ "\nStepping back one dimension.")
                  (setq step 2))
           (setq hgt v step 4)))
      ((= step 4)
         (setq v (cbk:askbase T))
         (if (eq v 'CBK-BACK)
           (progn (princ "\nStepping back one dimension.")
                  (setq step 3))
           (setq base v step 5)))))

  ;; -- 2. the eight corners.  The block is a pictorial: the back face
  ;;       is the front face slid up-right at 45 degrees, and it is slid
  ;;       by the TRUE length over root 2 on each axis, so the receding
  ;;       edge measures the length that was typed
  (setq d  (/ len (sqrt 2.0))
        pa (cbk:pt base 0.0 0.0)              ; front face, anticlockwise
        pb (cbk:pt base wid 0.0)              ; from the base point
        pc (cbk:pt base wid hgt)
        pd (cbk:pt base 0.0 hgt)
        qb (cbk:pt base (+ wid d) d)          ; back face, three of the
        qc (cbk:pt base (+ wid d) (+ hgt d))  ; four -- its bottom left
        qd (cbk:pt base d (+ hgt d)))         ; corner is never reached

  ;; -- 3. draw it, all of it inside one undo group
  (setvar "CMDECHO" 0)
  (setvar "OSMODE"  0)
  (command "_.UNDO" "_Begin")
  (setq undo-open t)

  (cbk:ensure-layer cbk:*layer* cbk:*laycolor*)
  ;; the front face, then the two faces the viewpoint shows.  The back
  ;; bottom left corner is a corner of the block, but all three edges
  ;; that meet there are hidden behind it -- so it is not even computed
  ;; above, and no line below reaches it.  Drawing those three is what
  ;; would turn a solid into a wire cage
  (cbk:line pd pc)                            ; front face
  (cbk:line pc pb)
  (cbk:line pb pa)
  (cbk:line pa pd)
  (cbk:line pd qd)                            ; top face, back edge and
  (cbk:line qd qc)                            ; the two receding edges
  (cbk:line pc qc)
  (cbk:line qc qb)                            ; right face, back edge
  (cbk:line pb qb)                            ; and its receding edge

  ;; -- 4. the three dimensions, in their own layer and style
  (setvar "CLAYER" (cbk:ensure-layer cbk:*dimlayer* cbk:*dimcolor*))
  (setq havestyle (cbk:setstyle cbk:*style*))
  (if (not havestyle)
    (princ (strcat "\n** This drawing has no \"" cbk:*style*
                   "\" dimension style -- dims drawn in \""
                   (getvar "DIMSTYLE")
                   "\" instead.  Create the style (or start from the"
                   " standard template) and re-run.")))

  (setq off  cbk:*dimoff*
        made 0)
  ;; the length, aligned along the top-left receding edge and pushed
  ;; out on the far side of it, away from the top face
  (if (cbk:dim 'ALIGNED pd qd
               (cbk:pt base (- (/ d 2.0) (/ off (sqrt 2.0)))
                            (+ hgt (/ d 2.0) (/ off (sqrt 2.0))))
               havestyle)
    (setq made (1+ made)))
  ;; the height, up the left of the front face
  (if (cbk:dim 'VERT pa pd (cbk:pt base (- off) (/ hgt 2.0)) havestyle)
    (setq made (1+ made)))
  ;; the width, along under it
  (if (cbk:dim 'HORIZ pb pa (cbk:pt base (/ wid 2.0) (- off)) havestyle)
    (setq made (1+ made)))

  ;; -- 5. put the drawing back the way it was
  (cbk:restyle odim)
  (command "_.UNDO" "_End")
  (setq undo-open nil)
  (cbk:sysrestore)
  (setq *error* olderr)

  (princ (strcat "\nCUSTBLOCK: " (cbk:num len) " x " (cbk:num wid)
                 " x " (cbk:num hgt) " block drawn on layer "
                 cbk:*layer* " -- 9 lines and " (itoa made)
                 " dimension" (if (= made 1) "" "s") " on layer "
                 cbk:*dimlayer*
                 (if havestyle
                   (strcat " in style " cbk:*style* ".")
                   " (current style).")))
  (princ))

(defun c:CUSTBLOCKVER ()
  (princ (strcat "\nCUSTBLOCK " *custblock-version*))
  (princ))

(princ (strcat "\nCUSTBLOCK " *custblock-version*
               " loaded -- type CUSTBLOCK to draw a block from its"
               " length, width and height (layer \"" cbk:*layer*
               "\", dims \"" cbk:*style* "\")."))
(princ)
