;;; ===================================================================
;;; TYDRN.LSP                                          AutoCAD 2018
;;; -------------------------------------------------------------------
;;; Commands: TYDRN            the cleanup pass below
;;;           TYLERDRONESUITE  TYDRN, PADDLE and the shop's CDIM in the
;;;                            order the work has to happen in, with one
;;;                            highlight carried through every stage
;;;
;;; Drawing cleanup routine that applies three fixes in one pass:
;;;
;;;   1. TEXT  - every highlighted (pre-selected) text entity is
;;;              switched to style ROMANC at height 4.5, with color,
;;;              linetype and lineweight forced to BYLAYER.
;;;              If nothing is highlighted when the command starts you
;;;              are prompted to select text; pressing Enter at that
;;;              prompt processes ALL text in the drawing.
;;;
;;;   2. POOL POINTS - every POINT entity on layer POOL is moved to
;;;              layer POINTS with color / linetype / lineweight all
;;;              set to BYLAYER (POINTS is magenta, so they show pink).
;;;
;;;   3. ANCHOR POINTS - every POINT entity on layer ANCHORS is given
;;;              an explicit magenta (ACI 6) color - the same pink as
;;;              the points - but stays on the ANCHORS layer.
;;;
;;;   4. ORIENT - after the conversion the processed text is rotated
;;;              flat so it reads west -> east, right side up
;;;              (absolute angle 0).  Each text pivots about its own
;;;              insertion point - the labels share that point in
;;;              space with the POINT they belong to - so every label
;;;              stays anchored to its point.  Set
;;;              *tydrn-orient-angle* to nil to only flip upside-down
;;;              text instead ("Most readable").
;;;
;;; The ROMANC text style and the POINTS layer are created if they do
;;; not already exist.  Locked layers are unlocked for the duration of
;;; the command and re-locked afterwards.  The whole run is wrapped in
;;; a single undo group.
;;; ===================================================================

(setq *tydrn-version* "v1.10")   ; announced on load; release_lisp.py
                                   ; stamps the dated twin in releases/

(vl-load-com)

;; ---------------------------------------------------------------
;; Configuration
;; ---------------------------------------------------------------
(setq *tydrn-text-style*  "ROMANC"
      *tydrn-text-font*   "romanc.shx"
      *tydrn-text-height* 4.5
      *tydrn-pool-layer*  "POOL"
      *tydrn-dest-layer*  "POINTS"
      *tydrn-anch-layer*  "ANCHORS"
      *tydrn-pink*        6           ; ACI 6 = magenta / pink
      *tydrn-orient-angle* 0.0)       ; absolute text angle in degrees
                                      ; (0 = read west->east, right
                                      ; side up); nil = only flip
                                      ; upside-down text ("Most
                                      ; readable")

;; ---------------------------------------------------------------
;; Helpers
;; ---------------------------------------------------------------

;; Make sure the target text style exists.
(defun tydrn:ensure-style (name font)
  (if (null (tblsearch "STYLE" name))
    (entmake
      (list '(0 . "STYLE")
            '(100 . "AcDbSymbolTableRecord")
            '(100 . "AcDbTextStyleTableRecord")
            (cons 2 name)
            '(70 . 0)
            '(40 . 0.0)                ; height 0 = not fixed
            '(41 . 1.0)                ; width factor
            '(50 . 0.0)                ; oblique angle
            '(71 . 0)
            (cons 3 font)
            '(4 . ""))))
  (tblsearch "STYLE" name))

;; Make sure the target layer exists.
(defun tydrn:ensure-layer (name color / rec ed flags col fixed)
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

;; Unlock every layer in NAMES that is currently locked and return the
;; list of layer objects that were unlocked (so they can be re-locked).
(defun tydrn:unlock-layers (names doc / layers obj unlocked)
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

(defun tydrn:relock-layers (objs)
  (foreach obj objs (vla-put-Lock obj :vlax-true)))

;; Reset color / linetype / lineweight of a vla-object to BYLAYER.
(defun tydrn:force-bylayer (obj)
  (vla-put-Color obj acByLayer)
  (vla-put-Linetype obj "ByLayer")
  (vla-put-Lineweight obj acLnWtByLayer))

;; Rotate a text to the target orientation.  Setting the Rotation
;; property pivots the text about its insertion/alignment point; the
;; point labels share that point in space with the POINT entity they
;; belong to, so each label swings around its own point and stays
;; anchored to it.  With *tydrn-orient-angle* set, the text is turned
;; to that absolute angle; with it nil, only upside-down text (angle
;; in (90, 270] degrees) is flipped 180.
(defun tydrn:orient (obj / cur target)
  (setq cur (rem (vla-get-Rotation obj) (* 2.0 pi)))   ; radians
  (if (< cur 0.0) (setq cur (+ cur (* 2.0 pi))))
  (setq target
        (if *tydrn-orient-angle*
          (* pi (/ *tydrn-orient-angle* 180.0))
          (if (and (> cur (* 0.5 pi)) (<= cur (* 1.5 pi)))
            (rem (+ cur pi) (* 2.0 pi))
            cur)))
  (if (not (equal cur target 1e-8))
    (vla-put-Rotation obj target)))

;; Collect the distinct layer names used by the entities of a
;; selection set.
(defun tydrn:sel-layers (ss / i lay result)
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq lay (cdr (assoc 8 (entget (ssname ss i)))))
        (if (not (member (strcase lay) result))
          (setq result (cons (strcase lay) result)))
        (setq i (1+ i)))))
  result)

;; The selection TYLERDRONESUITE hands this stage, through a global
;; rather than a pickfirst set: the pickfirst route needs PICKFIRST at
;; 1, and switching it on round a stage left a drafter who works at 0
;; at 1 whenever a stage failed or was Esc'd (see the suite's header).
;; It holds (NAME SELECTION), is read only by the command NAME, and is
;; cleared at the read whoever it was for -- and by the handler, for a
;; failure before the read -- so it never outlives the call it was made
;; for.  PADDLE reads the same global the same way.
(setq *calofin-handoff* nil)

;; The handed-over selection narrowed to TYPES (the filter this
;; command's own (ssget "_I") uses) and to what is still in the
;; drawing, or nil when nothing was handed to TYDRN.
(defun tydrn:handed (types / h ss i e)
  (setq h                 *calofin-handoff*
        *calofin-handoff* nil)
  (if (and (listp h) (= (car h) "TYDRN") (cadr h))
    (progn
      (setq ss (ssadd) i 0)
      (repeat (sslength (cadr h))
        (setq e (ssname (cadr h) i)
              i (1+ i))
        (if (and (entget e) (wcmatch (cdr (assoc 0 (entget e))) types))
          (ssadd e ss)))
      (if (< 0 (sslength ss)) ss))))

;; ---------------------------------------------------------------
;; Main command
;; ---------------------------------------------------------------
(defun C:TYDRN (/ *error* doc unlocked mark-open
                  ss-text ss-pool ss-anch i ent obj
                  n-text n-pool n-anch)

  ;; The handler is LOCAL to this command (STANDARDS 5): it used to be
  ;; installed by swapping the global *error*, which left this tool's
  ;; cleanup live for whatever ran next if a run ever ended without the
  ;; swap back.  It sees doc / unlocked / mark-open through dynamic
  ;; scope, and closes only the mark this run opened -- the close can
  ;; itself throw when the failure came before StartUndoMark, and a
  ;; throw inside *error* is the one error nothing can catch.
  (defun *error* (msg)
    ;; locked layers come back FIRST so nothing below can skip them
    ;; through the catch: a Lock put that throws must not skip the
    ;; mark close below -- a throw inside *error* is uncatchable
    (if unlocked (vl-catch-all-apply 'tydrn:relock-layers (list unlocked)))
    (setq unlocked nil)
    (setq *calofin-handoff* nil)     ; one never read goes with the run
    (if mark-open (vl-catch-all-apply 'vla-EndUndoMark (list doc)))
    (setq mark-open nil)
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nTYDRN error: " msg)))
    (if lzd:report (lzd:report "TYDRN" *tydrn-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "TYDRN" *tydrn-version*))

  (setq doc      (vla-get-ActiveDocument (vlax-get-acad-object))
        unlocked nil
        n-text 0  n-pool 0  n-anch 0)

  (vla-StartUndoMark doc)
  (setq mark-open T)

  ;; Make sure the style and destination layer are available.
  (tydrn:ensure-style *tydrn-text-style* *tydrn-text-font*)
  (tydrn:ensure-layer *tydrn-dest-layer* *tydrn-pink*)

  ;; ------------------------------------------------------------
  ;; 1. Text: highlighted selection, else prompt, Enter = all text
  ;; ------------------------------------------------------------
  (setq ss-text (tydrn:handed "TEXT"))
  (if (null ss-text)
    (setq ss-text (ssget "_I" '((0 . "TEXT")))))
  (if lzd:watch (lzd:watch ss-text) ss-text)
  (if (null ss-text)
    (progn
      (prompt "\nSelect text to update <Enter = all text in model space>: ")
      (setq ss-text (ssget '((0 . "TEXT"))))
      (if lzd:watch (lzd:watch ss-text) ss-text)
      ;; Enter means the TRACE's text, which is in model space: a
      ;; bare "_X" also took every layout's title-block and sheet
      ;; text and restyled it to the trace's font, height and angle
      (if (null ss-text)
        (setq ss-text (ssget "_X" '((0 . "TEXT") (410 . "Model")))))))

  ;; ------------------------------------------------------------
  ;; 2/3. Points on POOL and ANCHORS, anywhere in the drawing
  ;; ------------------------------------------------------------
  (setq ss-pool (ssget "_X" (list '(0 . "POINT") (cons 8 *tydrn-pool-layer*)))
        ss-anch (ssget "_X" (list '(0 . "POINT") (cons 8 *tydrn-anch-layer*))))

  ;; Unlock every layer we are about to touch.
  (setq unlocked
        (tydrn:unlock-layers
          (append (list *tydrn-pool-layer*
                        *tydrn-anch-layer*
                        *tydrn-dest-layer*)
                  (tydrn:sel-layers ss-text))
          doc))

  ;; Text -> ROMANC / 4.5 / BYLAYER
  (if ss-text
    (progn
      (setq i 0)
      (while (< i (sslength ss-text))
        (setq ent (ssname ss-text i)
              obj (vlax-ename->vla-object ent))
        (vla-put-StyleName obj *tydrn-text-style*)
        (vla-put-Height obj *tydrn-text-height*)
        (tydrn:force-bylayer obj)
        (vl-catch-all-apply 'tydrn:orient (list obj))
        (setq n-text (1+ n-text)
              i      (1+ i)))))

  ;; POOL points -> POINTS layer, everything BYLAYER
  (if ss-pool
    (progn
      (setq i 0)
      (while (< i (sslength ss-pool))
        (setq obj (vlax-ename->vla-object (ssname ss-pool i)))
        (vla-put-Layer obj *tydrn-dest-layer*)
        (tydrn:force-bylayer obj)
        (setq n-pool (1+ n-pool)
              i      (1+ i)))))

  ;; ANCHORS points -> pink (ACI 6), same layer
  (if ss-anch
    (progn
      (setq i 0)
      (while (< i (sslength ss-anch))
        (setq obj (vlax-ename->vla-object (ssname ss-anch i)))
        (vla-put-Color obj *tydrn-pink*)
        (setq n-anch (1+ n-anch)
              i      (1+ i)))))

  ;; Re-lock whatever we unlocked and close the undo group.
  (tydrn:relock-layers unlocked)
  (setq unlocked nil)
  (vla-EndUndoMark doc)
  (setq mark-open nil)

  (princ (strcat "\nTYDRN done: "
                 (itoa n-text) " text -> " *tydrn-text-style*
                 " h" (rtos *tydrn-text-height* 2 2)
                 " oriented W->E, "
                 (itoa n-pool) " point(s) POOL -> " *tydrn-dest-layer*
                 ", "
                 (itoa n-anch) " ANCHORS point(s) -> pink."))
  (if lzd:end (lzd:end "TYDRN"))
  (princ))

;;; ===================================================================
;;; TYLERDRONESUITE - the drone trace, start to finish
;;; -------------------------------------------------------------------
;;; TYDRN, then PADDLE, then CDIM, in that order because that is the
;;; order the work has to happen in: the points have to be on the right
;;; layer before PADDLE can find the perimeter features to pad, and
;;; CDIM is the finisher, tidying whatever dimensioning the drawing
;;; carries once everything else is in.  (AUTODIM sat between PADDLE
;;; and CDIM here once; the operator this suite is for does not want it
;;; in the flow, and putting it back is one name in *tydrn-suite*
;;; below.)
;;;
;;; CDIM IS NOT ONE OF OURS.  It is the in-house command this shop has
;;; on every machine; calofin has named it for a long time without ever
;;; running it -- covercheck, linfincheck and spacheck all end their
;;; reports by telling you to run CDIM over the strays they found, and
;;; each carries it in a tunable (*cchk-dimfix-cmd* and friends).  This
;;; is the first place that actually calls it, and it is *tydrn-finish-
;;; cmd* here for the same reason: a shop that calls it something else
;;; retunes it, and one that has no such command sets it nil.
;;;
;;; Nothing is skipped or reworded - each stage is the command itself,
;;; asking its own questions, so anything learned about TYDRN, PADDLE
;;; or AUTODIM stays true here.  The suite supplies the order, and the
;;; highlight.
;;;
;;; THE HIGHLIGHT IS MADE ONCE AND CARRIED THROUGH EVERY STAGE.  The
;;; calofin stages want the same thing selected - TYDRN the text in it,
;;; PADDLE the perimeter - and AutoCAD clears the pickfirst set the
;;; moment a command consumes it, so run by hand the trace has to be
;;; highlighted once per stage.  Here it is highlighted once in total:
;;; the set is read at the start and handed to each stage in
;;; *calofin-handoff*, which the stage reads where it would have read
;;; the pickfirst set (tydrn:handed, and PADDLE's and AUTODIM's own
;;; copies of it), so every stage opens with exactly what the operator
;;; picked and takes from it whatever its own filter takes.
;;; Highlight nothing and the suite asks once, up front; press Enter
;;; there and each stage asks on its own, exactly as it does alone.
;;;
;;; THE CARRIED SET GROWS BY WHAT EACH STAGE DRAWS, because a later
;;; stage is meant to see the earlier ones' work - that is the entire
;;; reason for the order.  It is what let AUTODIM, when it was in this
;;; list, open with the pads PADDLE had just dropped (its filter takes
;;; INSERTs for exactly those), and it is what any stage put into
;;; *tydrn-suite* after another gets for free -- as long as it reads
;;; *calofin-handoff*, as TYDRN, PADDLE and AUTODIM do; one that does
;;; not simply asks for its own selection.
;;;
;;; CDIM IS HANDED A CLEARED SELECTION.  It works over the drawing's
;;; dimensioning, which is in nobody's original highlight; typed by
;;; hand it starts with nothing selected too, so clearing is what keeps
;;; it behaving the way its operator knows it.
;;;
;;; PICKFIRST IS NOT TOUCHED.  The set used to go over as a pickfirst
;;; set, with PICKFIRST forced to 1 round the stages because at 0
;;; sssetfirst still highlights but ssget "_I" reads nothing.  But an
;;; Esc inside a stage runs only that stage's handler (below), so the
;;; restore never ran and a drafter who works at 0 was left at 1 for
;;; good, with nothing said.  The handoff global needs no setting of
;;; theirs, and a stage clears it itself.
;;;
;;; EACH STAGE KEEPS ITS OWN UNDO GROUP, so three U's back the suite
;;; out, one per stage.  That is deliberate, and it is XYPLOT's
;;; reasoning about its ABHD handoff: a stage that went well should not
;;; have to be undone to get at one that did not.
;;;
;;; HOW A STAGE IS REACHED, and why it is not (command)/(vl-cmdf).
;;; The command processor DOES NOT KNOW AUTOLISP COMMANDS.  Typing
;;; TYDRN works only because the command line, failing to recognise the
;;; name, falls back to trying c:TYDRN -- and (command)/(vl-cmdf) skip
;;; that fallback, so through them every stage came back "Unknown
;;; command" and the suite "ran" in seconds while running nothing.
;;; (PGP aliases are invisible to them the same way.)  So:
;;;
;;;   * The three calofin stages are their c: functions, CALLED
;;;     DIRECTLY.  Nothing is lost by it: the prompts live in the
;;;     functions, so each stage still asks its own questions exactly
;;;     as it does when it is typed.
;;;   * The finisher is called directly too when this session's
;;;     AutoLISP defines it.  When it does not -- .NET, ARX or a PGP
;;;     alias -- it goes through vla-SendCommand, the one door that is
;;;     literally "as typed": the text is queued on the command line
;;;     itself, so whatever answers to the operator's typing answers to
;;;     this.  Queued input runs when this routine ends; the finisher
;;;     is last, so last is exactly where it lands, just after the
;;;     done message.  A CDIM that really is absent costs one "Unknown
;;;     command" line there, after all the work is done.
;;;
;;; Esc in any stage stops the suite there - an AutoLISP error unwinds
;;; to the command line, so the stages after it never start.  What ran
;;; before it stays run, which is why the check below happens first.
;;; (On that path the stage's own *error* handler is the one AutoCAD
;;; calls - the innermost binding wins, and each stage declares its own
;;; as a local, STANDARDS section 5 - so the stage cleans up after
;;; itself, the handoff included, and this command's handler does not
;;; run.  That is why the suite borrows nothing it would have to put
;;; back.  Esc at the suite's OWN prompt, where no stage is running,
;;; does reach the handler below.)
;;;
;;; THE CHECK COVERS THE CALOFIN STAGES AND NOT CDIM, on purpose.
;;; boundp can only see commands AutoLISP defined; an in-house command
;;; is as likely to be .NET, ARX or a PGP alias, and none of those
;;; answer to it.  Refusing to run because a check cannot see something
;;; that is plainly there would be worse than the failure it guards
;;; against -- and by the time CDIM is reached the stages that needed
;;; guarding have already run.
;;; ===================================================================

;; The calofin stages, in order -- also the pre-flight list.  AUTODIM
;; used to sit after PADDLE; the operator wants it out of the flow, so
;; putting it back is just adding the name back here.
(setq *tydrn-suite* '("TYDRN" "PADDLE"))

;; Run last, after the stages above.  Not calofin's -- see the header.
;; nil runs nothing and the suite stops after AUTODIM.
(setq *tydrn-finish-cmd* "CDIM")

;; Every stage the run will go through, the finisher included.  The
;; "1 of 4" counting comes off this, so it can never disagree with what
;; actually runs.
(defun tydrn:stages ()
  (if *tydrn-finish-cmd*
    (append *tydrn-suite* (list *tydrn-finish-cmd*))
    *tydrn-suite*))

;; Is C:<name> defined in this session?  (XYPLOT's boundp test, with
;; the name computed rather than quoted.)
(defun tydrn:has (name)
  (boundp (read (strcat "c:" name))))

;; "PADDLE and CDIM" -- the way lists of names read in the messages.
(defun tydrn:namelist (names / out n i nm)
  (setq out "" n (length names) i 0)
  (foreach nm names
    (setq out (strcat out
                      (cond ((= i 0) "")
                            ((= i (1- n)) (if (= n 2) " and " ", and "))
                            (t ", "))
                      nm)
          i   (1+ i)))
  out)

;; ---------------------------------------------------------------
;; Carrying one highlight through the stages
;; ---------------------------------------------------------------

;; The entity names in a selection set, as a plain list.  The set
;; itself is no good to keep: it has to be rebuilt before each stage
;; anyway, because by then some of what is in it may be gone.
(defun tydrn:ss->list (ss / out i)
  (setq i 0)
  (if ss
    (repeat (sslength ss)
      (setq out (cons (ssname ss i) out)
            i   (1+ i))))
  (reverse out))

;; Everything drawn after ENT, which is the entlast taken before a
;; stage ran.  nil for ENT means the drawing was empty then, so the
;; walk starts at the first entity.
(defun tydrn:since (ent / e out)
  (setq e (if ent (entnext ent) (entnext)))
  (while e
    (setq out (cons e out)
          e   (entnext e)))
  (reverse out))

;; A selection set of the members of LST that are still in the drawing.
;; A stage is free to erase what it replaces, and an erased ename in a
;; set is not something AutoCAD will hand to the next command -- so the
;; set is rebuilt from what survives, every time, rather than kept.
;; nil when nothing survives: it becomes the set half of
;; *calofin-handoff*, and a nil set there is what the stage readers
;; (tydrn:handed, paddle--handed, ad:handed) treat as "nothing handed",
;; so the stage asks for its own selection instead of acting on a dead one.
(defun tydrn:live-ss (lst / ss e)
  (setq ss (ssadd))
  (foreach e lst
    (if (and e (entget e)) (ssadd e ss)))
  (if (< 0 (sslength ss)) ss))

;; The handler is LOCAL to the command (STANDARDS section 5), as every
;; other handler in this file is.  The suite changes no setting of the
;; drafter's, so all it has to put right is a handoff no stage read.
;; It runs for an Esc at the suite's own selection prompt; inside a
;; stage the stage's own handler is the innermost one and this never
;; sees it (see the header) -- which is why the handoff is a global
;; the stage clears itself, and not a PICKFIRST borrow this would
;; have to put back.
(defun c:TYLERDRONESUITE ( / *error* missing nm step carry mark stages)
  (defun *error* (msg)
    (setq *calofin-handoff* nil)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nTYLERDRONESUITE error: " msg)))
    (if lzd:report (lzd:report "TYLERDRONESUITE" *tydrn-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "TYLERDRONESUITE" *tydrn-version*))
  ;; Every calofin stage is checked BEFORE any of them runs.  Half a
  ;; suite is worse than none: TYDRN would have moved the points and
  ;; the operator would find out only mid-run that the padding they ran
  ;; this for was never going to happen.
  (setq missing nil)
  (foreach nm *tydrn-suite*
    (if (not (tydrn:has nm)) (setq missing (cons nm missing))))
  (setq missing (reverse missing))
  (if missing
    (progn
      (princ (strcat "\nTYLERDRONESUITE needs " (tydrn:namelist missing)
                     ", which " (if (= 1 (length missing)) "is" "are")
                     " not loaded here."))
      (princ "\n  APPLOAD the missing file - or LAZPASS.lsp, which is the")
      (princ "\n  whole build in one - and run it again.  Nothing has been")
      (princ "\n  changed."))
    (progn
      (setq stages (tydrn:stages))
      (princ (strcat "\nTYLERDRONESUITE: " (tydrn:namelist stages) "."))
      (princ "\n  One highlight is carried through every stage, so the")
      (princ "\n  trace is picked once rather than once per command.")
      (princ "\n  Each stage is its own undo group, so a stage that went")
      (princ "\n  well is not undone to get at one that did not.  Esc in")
      (princ "\n  any stage stops the suite there.")

      ;; What the operator highlighted before typing the command.  If
      ;; that is nothing, ask once here rather than three times over.
      (setq carry (tydrn:ss->list (cadr (ssgetfirst))))
      (if (null carry)
        (progn
          (princ "\n\nHighlight the trace once and every stage gets it.")
          (princ "\nSelect the trace <Enter = let each stage ask on its own>: ")
          (setq carry (tydrn:ss->list (ssget)))))

      (setq step 0)
      (foreach nm stages
        (setq step (1+ step))
        (princ (strcat "\n\n--- " (itoa step) " of " (itoa (length stages))
                       ": " nm " ---"))
        ;; Hand this stage the highlight through *calofin-handoff*
        ;; (see tydrn:handed) -- or, for the finisher, nothing: CDIM
        ;; works on the dimensions AUTODIM has just made, which are in
        ;; nobody's original pick.  The pickfirst set is cleared either
        ;; way, so nothing is left gripped for a stage's own commands
        ;; to act on, and so CDIM starts with nothing selected, as it
        ;; does when it is typed.
        (sssetfirst nil nil)
        (setq *calofin-handoff*
              (if (member nm *tydrn-suite*)
                (list (strcase nm) (tydrn:live-ss carry))))
        (setq mark (entlast))
        ;; NOT (command)/(vl-cmdf): the command processor does not know
        ;; AutoLISP commands (typing works only through the command
        ;; line's own c: fallback, which those skip), so through them
        ;; every stage came back "Unknown command".  See the header.
        (cond
          ((or (member nm *tydrn-suite*) (tydrn:has nm))
           ;; An AutoLISP command, here, now: the c: function itself.
           ;; Its prompts live in it, so it asks its own questions
           ;; exactly as it does when it is typed.
           (apply (read (strcat "c:" nm)) nil))
          (t
           ;; .NET, ARX or a PGP alias: queue it on the command line
           ;; itself, literally as typed -- the one door all three
           ;; answer to.  Queued input runs when this routine ends,
           ;; which for the last stage is exactly where it belongs.
           (princ "\n  (queued on the command line - it runs as the suite closes)")
           (vla-SendCommand (vla-get-ActiveDocument (vlax-get-acad-object))
                            (strcat nm " "))))
        (setq *calofin-handoff* nil)    ; a stage that never read it
        ;; Grow the carried set by what this stage drew, so the next
        ;; one sees it.  Only worth doing while a calofin stage is
        ;; still to come -- the finisher gets a cleared selection.
        (if (member nm *tydrn-suite*)
          (setq carry (append carry (tydrn:since mark)))))

      (princ (strcat "\n\nTYLERDRONESUITE done - all "
                     (itoa (length stages)) " stages ran."))))
  (if lzd:end (lzd:end "TYLERDRONESUITE"))
  (princ))


(defun c:TYDRNVER ()
  (princ (strcat "\nTYDRN " *tydrn-version*))
  (princ))

;;; -------------------- self tests --------------------------------------
;; What LAZDIAG runs on the drafter's machine after this tool fails, and
;; writes into the report: the tool's own helpers on inputs whose answers
;; are KNOWN, so the report says whether the arithmetic was sound where
;; it ran.  (label expression expected) passes when the value is equal
;; to expected (to 1e-6); (label expression) passes when it is not nil,
;; and the value is written down either way.  Nothing here may prompt,
;; draw or (command): it is evaluated from inside *error*.
;; tests/test_selftests.py runs every entry in the VM at both tiers.
(defun tydrn:selftests ()
  (list
    (list "namelist joins two names with an and"
          '(tydrn:namelist '("PADDLE" "CDIM"))            "PADDLE and CDIM")
    (list "namelist puts the serial comma on three"
          '(tydrn:namelist '("TYDRN" "PADDLE" "CDIM"))    "TYDRN, PADDLE, and CDIM")
    (list "namelist of none is the empty string"
          '(tydrn:namelist nil)                           "")
    (list "stages names TYDRN and ends on the finisher; value is the 'of N' count"
          '(if (and (member "TYDRN" (tydrn:stages))
                    (equal (last (tydrn:stages))
                           (if *tydrn-finish-cmd* *tydrn-finish-cmd* (last *tydrn-suite*))))
             (length (tydrn:stages))))
    (list "has sees this file's own command"
          '(tydrn:has "TYDRN")                            T)
    (list "has says no for a command nobody loaded"
          '(tydrn:has "NOSUCHCOMMANDXYZ")                 nil)
    (list "live-ss of nothing is nil, not an empty set"
          '(tydrn:live-ss nil)                            nil)
    (list "the text height knob is a positive number"
          '(if (and (numberp *tydrn-text-height*) (> *tydrn-text-height* 0))
             *tydrn-text-height*))
    (list "the orient knob is nil (flip only) or an angle"
          '(or (null *tydrn-orient-angle*) (numberp *tydrn-orient-angle*))  T)))

(foreach c '("TYDRN" "TYLERDRONESUITE")
  (setq *calofin-selftests*
        (cons (cons c 'tydrn:selftests) *calofin-selftests*)))

;; Quiet inside the whole build: LAZPASS.lsp and
;; CALOFIN-LOADER.lsp set the flag while they load their members,
;; because one file's greeting is a greeting and sixty-three of
;; them is a wall the drafter scrolls past in every drawing they
;; open.  APPLOADed alone the flag is nil and this prints, which
;; is the one time somebody wants to be told.  CALVER reports the
;; whole roster whenever it is asked.
(if (not *calofin-quiet*)
  (princ (strcat "\nTYDRN " *tydrn-version*
                 " loaded.  Type TYDRN to run, or TYLERDRONESUITE"
                 " for the whole trace.")))
(princ)
