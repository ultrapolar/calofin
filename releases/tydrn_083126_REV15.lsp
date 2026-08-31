;;; ===================================================================
;;; TYDRN.LSP                                          AutoCAD 2018
;;; -------------------------------------------------------------------
;;; Commands: TYDRN             the cleanup below
;;;           TYLERDRONESUITE  TYDRN, PADDLE, then CDIM, each
;;;                            handed the same one highlight
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

(setq *tydrn-version* "v1.5")   ; announced on load; release_lisp.py
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
(defun tydrn:ensure-layer (name color)
  (if (null (tblsearch "LAYER" name))
    (entmake
      (list '(0 . "LAYER")
            '(100 . "AcDbSymbolTableRecord")
            '(100 . "AcDbLayerTableRecord")
            (cons 2 name)
            '(70 . 0)
            (cons 62 color)
            '(6 . "Continuous"))))
  (tblsearch "LAYER" name))

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

;; ---------------------------------------------------------------
;; Error handler - restore locked layers and close the undo group
;; even if the user hits Esc or something fails mid-run.
;; ---------------------------------------------------------------
(defun tydrn:error (msg)
  (if *tydrn-unlocked* (tydrn:relock-layers *tydrn-unlocked*))
  (setq *tydrn-unlocked* nil)
  (if *tydrn-doc* (vla-EndUndoMark *tydrn-doc*))
  (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
    (princ (strcat "\nTYDRN error: " msg)))
  (if *tydrn-old-error* (setq *error* *tydrn-old-error*))
  (princ))

;; ---------------------------------------------------------------
;; Main command
;; ---------------------------------------------------------------
(defun C:TYDRN (/ ss-text ss-pool ss-anch i ent obj
                  n-text n-pool n-anch)

  (setq *tydrn-old-error* *error*
        *error*           tydrn:error
        *tydrn-doc*       (vla-get-ActiveDocument (vlax-get-acad-object))
        *tydrn-unlocked*  nil
        n-text 0  n-pool 0  n-anch 0)

  (vla-StartUndoMark *tydrn-doc*)

  ;; Make sure the style and destination layer are available.
  (tydrn:ensure-style *tydrn-text-style* *tydrn-text-font*)
  (tydrn:ensure-layer *tydrn-dest-layer* *tydrn-pink*)

  ;; ------------------------------------------------------------
  ;; 1. Text: highlighted selection, else prompt, Enter = all text
  ;; ------------------------------------------------------------
  (setq ss-text (ssget "_I" '((0 . "TEXT"))))
  (if (null ss-text)
    (progn
      (prompt "\nSelect text to update <Enter = all text in drawing>: ")
      (setq ss-text (ssget '((0 . "TEXT"))))
      (if (null ss-text)
        (setq ss-text (ssget "_X" '((0 . "TEXT")))))))

  ;; ------------------------------------------------------------
  ;; 2/3. Points on POOL and ANCHORS, anywhere in the drawing
  ;; ------------------------------------------------------------
  (setq ss-pool (ssget "_X" (list '(0 . "POINT") (cons 8 *tydrn-pool-layer*)))
        ss-anch (ssget "_X" (list '(0 . "POINT") (cons 8 *tydrn-anch-layer*))))

  ;; Unlock every layer we are about to touch.
  (setq *tydrn-unlocked*
        (tydrn:unlock-layers
          (append (list *tydrn-pool-layer*
                        *tydrn-anch-layer*
                        *tydrn-dest-layer*)
                  (tydrn:sel-layers ss-text))
          *tydrn-doc*))

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

  ;; ------------------------------------------------------------
  ;; 4. Orient the converted text to read west -> east, right side
  ;;    up, each label pivoting about its insertion point (= the
  ;;    point it labels).
  ;; ------------------------------------------------------------
  (if ss-text
    (progn
      (setq i 0)
      (while (< i (sslength ss-text))
        (vl-catch-all-apply
          'tydrn:orient
          (list (vlax-ename->vla-object (ssname ss-text i))))
        (setq i (1+ i)))))

  ;; Re-lock whatever we unlocked and close the undo group.
  (tydrn:relock-layers *tydrn-unlocked*)
  (setq *tydrn-unlocked* nil)
  (vla-EndUndoMark *tydrn-doc*)
  (setq *error* *tydrn-old-error*)

  (princ (strcat "\nTYDRN done: "
                 (itoa n-text) " text -> " *tydrn-text-style*
                 " h" (rtos *tydrn-text-height* 2 2)
                 " oriented W->E, "
                 (itoa n-pool) " point(s) POOL -> " *tydrn-dest-layer*
                 ", "
                 (itoa n-anch) " ANCHORS point(s) -> pink."))
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
;;; the set is read at the start and put back with sssetfirst before
;;; each stage, so every stage opens with exactly what the operator
;;; picked and takes from it whatever its own filter takes.
;;; Highlight nothing and the suite asks once, up front; press Enter
;;; there and each stage asks on its own, exactly as it does alone.
;;;
;;; THE CARRIED SET GROWS BY WHAT EACH STAGE DRAWS, because a later
;;; stage is meant to see the earlier ones' work - that is the entire
;;; reason for the order.  It is what let AUTODIM, when it was in this
;;; list, open with the pads PADDLE had just dropped (its filter takes
;;; INSERTs for exactly those), and it is what any stage put into
;;; *tydrn-suite* after another gets for free.
;;;
;;; CDIM IS HANDED A CLEARED SELECTION.  It works over the drawing's
;;; dimensioning, which is in nobody's original highlight; typed by
;;; hand it starts with nothing selected too, so clearing is what keeps
;;; it behaving the way its operator knows it.
;;;
;;; PICKFIRST is forced to 1 for the run and put back afterwards.  With
;;; it at 0 sssetfirst still highlights but ssget "_I" reads nothing, and
;;; the handoff would go quietly missing - the one failure mode worth
;;; spending a sysvar to rule out.
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
;;; (On that path the stage's own *error* handler is the one that runs,
;;; so the suite's PICKFIRST restore does not; it is left at 1, the
;;; factory default, which is the cost of letting each stage keep its
;;; own cleanup.)
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
;; nil when nothing survives, which is what sssetfirst wants for
;; "clear it".
(defun tydrn:live-ss (lst / ss e)
  (setq ss (ssadd))
  (foreach e lst
    (if (and e (entget e)) (ssadd e ss)))
  (if (< 0 (sslength ss)) ss))

;; Put PICKFIRST back if Esc gets out before the run does.  Named and
;; paired with a global, the way tydrn:error already is in this file --
;; an *error* that closes over a local is a different thing to reason
;; about, and this file has one pattern for this already.
(defun tydrn:suite-error (msg)
  (if *tydrn-suite-pick* (setvar "PICKFIRST" *tydrn-suite-pick*))
  (setq *tydrn-suite-pick* nil)
  (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
    (princ (strcat "\nTYLERDRONESUITE error: " msg)))
  (if *tydrn-suite-old-error* (setq *error* *tydrn-suite-old-error*))
  (princ))

(defun c:TYLERDRONESUITE ( / missing nm step carry mark stages)
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

      ;; PICKFIRST at 0 would let sssetfirst highlight while ssget "_I"
      ;; read nothing, and the handoff would go quietly missing.  Put
      ;; back below, and by the error handler if Esc gets here first.
      (setq *tydrn-suite-pick*      (getvar "PICKFIRST")
            *tydrn-suite-old-error* *error*
            *error*                 tydrn:suite-error)
      (setvar "PICKFIRST" 1)

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
        ;; Hand this stage the highlight -- or, for the finisher,
        ;; clear it: CDIM works on the dimensions AUTODIM has just
        ;; made, which are in nobody's original pick.
        (sssetfirst nil (if (member nm *tydrn-suite*)
                          (tydrn:live-ss carry)
                          nil))
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
        ;; Grow the carried set by what this stage drew, so the next
        ;; one sees it.  Only worth doing while a calofin stage is
        ;; still to come -- the finisher gets a cleared selection.
        (if (member nm *tydrn-suite*)
          (setq carry (append carry (tydrn:since mark)))))

      (setvar "PICKFIRST" *tydrn-suite-pick*)
      (setq *tydrn-suite-pick* nil
            *error*            *tydrn-suite-old-error*)
      (princ (strcat "\n\nTYLERDRONESUITE done - all "
                     (itoa (length stages)) " stages ran."))))
  (princ))

(princ (strcat "\nTYDRN.LSP " *tydrn-version*
               " loaded.  Type TYDRN to run, or TYLERDRONESUITE"
               " for the whole trace."))
(princ)
