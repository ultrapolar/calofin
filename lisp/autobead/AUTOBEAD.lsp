;;; ==========================================================================
;;; AUTOBEAD.lsp
;;; --------------------------------------------------------------------------
;;; Commands:
;;;   AUTOBEAD          - bead the selected POOL lines
;;;   TUTORIALAUTOBEAD  - guided walkthrough (read it, or watch a live demo)
;;;   AUTOBEADVER       - report which revision is loaded
;;;
;;; Select POOL lines to "bead" (LINEs, ARCs, and polylines on any POOL*
;;; layer), then click the side to bead toward.  The selection is copied,
;;; joined into continuous chains, and each chain is offset 2" toward the
;;; clicked side using AutoCAD's native offset engine, so corners resolve
;;; automatically:
;;;   - convex (outside) corners have the excess trimmed
;;;   - concave (inside) corners are extended to meet
;;;   - arc / radius corners offset as true concentric arcs
;;; The finished beads land on the "Bead Track" layer.  The original pool
;;; geometry is never modified, and the whole run undoes with one U.
;;;
;;; Tunables: see the AUTOBEAD SETTINGS block below.
;;;
;;; --------------------------------------------------------------------------
;;; VERSION
;;;   This file ships under two names with identical contents:
;;;     AUTOBEAD.lsp                  - static name, for appload / startup
;;;     AUTOBEAD_MMDDYY_REV##.lsp     - dated name, so a stack can be
;;;                                     identified at a glance
;;;   Both report the same revision, so AUTOBEADVER tells you what someone
;;;   is actually running regardless of which filename they loaded.
;;;   Regenerate the dated copy with release.sh / release.ps1 -- do not
;;;   hand-copy, or the two will drift.
;;; ==========================================================================

(vl-load-com)

;; ---- AUTOBEAD SETTINGS ----------------------------------------------------

(setq *autobead-rev*    "REV01"      ; revision stamp
      *autobead-date*   "08/17/26"   ; release date, MM/DD/YY
      *autobead-offset* 2.0          ; bead offset, drawing units (2 = 2")
      *autobead-layer*  "Bead Track" ; output layer
      *autobead-filter* "POOL*"      ; selectable source layers
      *autobead-fuzz*   0.001)       ; endpoint join tolerance

;; ---- helpers --------------------------------------------------------------

(defun autobead-copy (e / o c)
  ;; Duplicate an entity in place and return the new ename (nil on failure).
  ;; This deliberately avoids the COPY command: COPY's point input depends on
  ;; the base-point / displacement prompt sequence and on the current copy
  ;; mode, so a mis-timed response silently translates the duplicate instead
  ;; of leaving it put.  vla-Copy always duplicates in place.
  (setq o (vlax-ename->vla-object e)
        c (vl-catch-all-apply 'vla-Copy (list o)))
  (if (vl-catch-all-error-p c)
    nil
    (vlax-vla-object->ename c)))

(defun autobead-minpt (e / o mn mx)
  ;; Lower-left corner of an entity's bounding box, or nil if unavailable.
  (setq o (vlax-ename->vla-object e))
  (if (vl-catch-all-error-p
        (vl-catch-all-apply 'vla-GetBoundingBox (list o 'mn 'mx)))
    nil
    (vlax-safearray->list mn)))

(defun autobead-inplace-p (src new / a b)
  ;; T if 'new' really did land on top of 'src'.  Guards against any future
  ;; copy path quietly displacing the geometry.
  (setq a (autobead-minpt src)
        b (autobead-minpt new))
  (or (null a) (null b) (< (distance a b) 1e-6)))

(defun autobead-gap (src bead / len p q)
  ;; Measured perpendicular gap between a finished bead and the chain it came
  ;; from, sampled at the bead's midpoint.  Purely diagnostic: it reports what
  ;; the offset actually produced rather than what it was asked for.
  (setq len (vl-catch-all-apply 'vlax-curve-getDistAtParam
              (list bead (vlax-curve-getEndParam bead))))
  (if (or (vl-catch-all-error-p len) (null len))
    nil
    (progn
      (setq p (vl-catch-all-apply 'vlax-curve-getPointAtDist
                (list bead (/ len 2.0))))
      (if (or (vl-catch-all-error-p p) (null p))
        nil
        (progn
          (setq q (vl-catch-all-apply 'vlax-curve-getClosestPointTo
                    (list src p)))
          (if (or (vl-catch-all-error-p q) (null q))
            nil
            (distance p q)))))))

(defun autobead-layers (ss / i lay res)
  ;; Distinct layer names present in a selection set.
  (setq res '() i 0)
  (while (< i (sslength ss))
    (setq lay (cdr (assoc 8 (entget (ssname ss i)))))
    (if (not (member lay res)) (setq res (cons lay res)))
    (setq i (1+ i)))
  (reverse res))

(defun autobead-newents (mark / e res)
  ;; Every entity added to the database after 'mark' that is still alive.
  (setq res '()
        e   (if mark (entnext mark) (entnext)))
  (while e
    (if (entget e) (setq res (cons e res)))
    (setq e (entnext e)))
  (reverse res))

(defun autobead-flush ()
  ;; Safety valve: if an internal command was left waiting for input
  ;; (e.g. OFFSET rejected a pick), feed it Enters until it terminates.
  (while (> (getvar "CMDACTIVE") 0) (command "")))

(defun autobead-ensure-layer (name / def flags)
  ;; Create the target layer if missing; thaw / unlock it if it exists
  ;; frozen or locked so the beads are visible and editable.
  (if (setq def (tblsearch "LAYER" name))
    (progn
      (setq flags (cdr (assoc 70 def)))
      (if (= 1 (logand 1 flags))                 ; frozen
        (command "._-layer" "_thaw" name ""))
      (if (= 4 (logand 4 flags))                 ; locked
        (command "._-layer" "_unlock" name "")))
    (entmake (list '(0 . "LAYER")
                   '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord")
                   (cons 2 name)
                   (cons 70 0)
                   (cons 62 1)                   ; color: red
                   (cons 6 "Continuous")))))

;; ---- engine ----------------------------------------------------------------
;; Everything that touches the drawing lives here, so AUTOBEAD and the
;; tutorial exercise exactly the same code path.  Returns the number of bead
;; objects created.

(defun autobead-build (ss dirpt / *error* beadoff layname fuzz
                                  oldcmd oldos oldpa temps
                                  mark copies ss2 chains mark2 news
                                  beadcount failcount c e i src dup drift
                                  gaps g)

  (setq beadoff *autobead-offset*
        layname *autobead-layer*
        fuzz    *autobead-fuzz*)

  ;; -- error handler: cancel stuck commands, purge temp geometry,
  ;;    restore system variables, close the undo group -------------------
  (defun *error* (msg)
    (autobead-flush)
    (foreach e temps
      (if (and e (entget e)) (entdel e)))
    (if oldpa (setvar "PEDITACCEPT" oldpa))
    (if oldos (setvar "OSMODE" oldos))
    (command "._undo" "_end")
    (if oldcmd (setvar "CMDECHO" oldcmd))
    (if (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*,*BREAK*"))
      (princ (strcat "\nAUTOBEAD error: " msg)))
    (princ))

  (setq oldcmd (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (command "._undo" "_begin")
  (setq oldos (getvar "OSMODE")
        oldpa (getvar "PEDITACCEPT")
        temps '()
        beadcount 0)

  (autobead-ensure-layer layname)
  (setvar "OSMODE" 0)          ; keep osnaps out of the internal commands
  (setvar "PEDITACCEPT" 1)     ; auto-accept line/arc -> pline conversion

  ;; 1) copy the selection in place so the originals are never touched
  (setq mark   (entlast)
        copies '()
        drift  nil
        i      0)
  (while (< i (sslength ss))
    (setq src (ssname ss i)
          dup (autobead-copy src))
    (if dup
      (progn
        (if (not (autobead-inplace-p src dup)) (setq drift T))
        (setq copies (cons dup copies))))
    (setq i (1+ i)))
  (setq copies (reverse copies)
        temps  copies)

  (cond
    ((null copies)
     (prompt "\nCould not copy the selection (locked source layer?)."))

    (drift
     (foreach e copies (if (entget e) (entdel e)))
     (setq temps '())
     (prompt (strcat "\nAborted: the working copies did not land on the"
                     " source geometry.\nNothing was drawn.")))

    (T
     ;; 2) join the copies into continuous polyline chains
     (setq ss2 (ssadd))
     (foreach c copies (ssadd c ss2))
     (command "._pedit" "_multiple" ss2 "" "_join" fuzz "")
     (autobead-flush)
     (setq chains (autobead-newents mark)
           temps  chains)

     ;; 3) offset each chain toward the click; native offset trims
     ;;    convex corners and extends concave ones automatically
     (setq failcount 0 gaps '())
     (foreach c chains
       (setq mark2 (entlast))
       (command "._offset" beadoff c "_non" dirpt "")
       (autobead-flush)
       (setq news (autobead-newents mark2))
       (if news
         (foreach e news
           (entmod (subst (cons 8 layname)
                          (assoc 8 (entget e))
                          (entget e)))
           ;; measure before the source chain is deleted
           (if (setq g (autobead-gap c e)) (setq gaps (cons g gaps)))
           (setq beadcount (1+ beadcount)))
         (setq failcount (1+ failcount)))
       ;; discard the temporary chain
       (if (entget c) (entdel c)))
     (setq temps '())

     ;; 4) report -- including what was actually built, so a bead that
     ;;    lands in the wrong place can be diagnosed from the command line
     (prompt (strcat "\n--- AUTOBEAD " *autobead-rev* " ---"
                     "\n  source layers : "
                     (apply 'strcat
                       (mapcar '(lambda (l) (strcat l " "))
                               (autobead-layers ss)))
                     "\n  objects picked: " (itoa (sslength ss))
                     "\n  joined chains : " (itoa (length chains))
                     "\n  offset asked  : " (rtos beadoff)
                     "\n  offset measured: "
                     (if gaps
                       (strcat (rtos (apply 'min gaps)) " to "
                               (rtos (apply 'max gaps)))
                       "n/a")
                     "\n  beads created : " (itoa beadcount)
                     " on " layname))
     (if (> failcount 0)
       (prompt (strcat "\n  " (itoa failcount)
                       " chain(s) could not be offset -- try clicking"
                       " farther from the pool line.")))))

  ;; -- restore --------------------------------------------------------------
  (setvar "PEDITACCEPT" oldpa)
  (setvar "OSMODE" oldos)
  (command "._undo" "_end")
  (setvar "CMDECHO" oldcmd)
  beadcount)

;; ---- AUTOBEAD --------------------------------------------------------------

(defun c:AUTOBEAD ( / ss dirpt stage done )
  (autobead-ensure-layer *autobead-layer*)
  ;; staged: Back (or Undo) at the direction click re-opens the selection
  (setq stage 1 done nil)
  (while (not done)
    (cond
      ((= stage 1)
       (prompt (strcat "\nSelect POOL lines to bead (layers "
                       *autobead-filter* "): "))
       (setq ss (ssget (list '(0 . "LINE,ARC,LWPOLYLINE,POLYLINE")
                             (cons 8 *autobead-filter*))))
       (if (null ss)
         (progn
           (prompt (strcat "\nNothing selected on a " *autobead-filter*
                           " layer."))
           (setq done T))
         (setq stage 2)))
      (T
       (initget "Back Undo")
       (setq dirpt (getpoint "\nClick the side to bead toward [Back]: "))
       (cond
         ((= (type dirpt) 'STR) (setq stage 1))
         ((null dirpt)
          (prompt "\nNo direction point picked.")
          (setq done T))
         (T (autobead-build ss dirpt) (setq done T))))))
  (princ))

;; ---- AUTOBEADVER -----------------------------------------------------------

(defun c:AUTOBEADVER ()
  (prompt (strcat "\nAUTOBEAD " *autobead-rev* "  (" *autobead-date* ")"
                  "\n  offset : " (rtos *autobead-offset*)
                  "\n  layer  : " *autobead-layer*
                  "\n  filter : " *autobead-filter*))
  (princ))

;; ==========================================================================
;;; TUTORIALAUTOBEAD
;;; --------------------------------------------------------------------------
;;; Two modes:
;;;   Read - a written walkthrough: every step, every check, every setting
;;;   Demo - draws a sample pool and beads it live, pausing at each stage
;;; ==========================================================================

(defun autobead-pause (msg)
  ;; Print a step heading and wait for Enter.
  (prompt (strcat "\n" msg))
  (getstring "\n      [Enter] to continue: ")
  (princ))

(defun autobead-say (lines)
  ;; Print a list of strings, one per line.
  (foreach l lines (prompt (strcat "\n" l)))
  (princ))

;; ---- read mode -------------------------------------------------------------

(defun autobead-tutorial-read ()
  (autobead-say
    (list
      ""
      "==========================================================="
      (strcat " AUTOBEAD " *autobead-rev* " - how it works")
      "==========================================================="
      ""
      "WHAT IT DOES"
      "  Draws a bead line at a fixed offset from your pool edge,"
      (strcat "  on the \"" *autobead-layer* "\" layer. Corners are resolved for")
      "  you: outside corners get trimmed, inside corners get"
      "  extended to meet, and radius corners stay concentric."
      ""
      "USING IT"
      "  1. Type AUTOBEAD."
      (strcat "  2. Select your pool lines. Only objects on a "
              *autobead-filter* " layer")
      "     can be picked, so a window select is safe - dimensions,"
      "     text and hatch are ignored."
      "  3. Click the side you want the bead on. One click sets the"
      "     direction for everything you selected."
      ""
      "CURRENT SETTINGS"
      (strcat "  offset distance : " (rtos *autobead-offset*)
              "   (drawing units)")
      (strcat "  output layer    : " *autobead-layer*)
      (strcat "  selectable from : " *autobead-filter*)
      (strcat "  join tolerance  : " (rtos *autobead-fuzz*))
      ""
      "WHAT IT CHECKS, IN ORDER"
      (strcat "   1. Output layer \"" *autobead-layer* "\" exists - creates it if not.")
      "   2. That layer is thawed and unlocked - fixes it if not, so"
      "      beads can never be drawn somewhere invisible."
      (strcat "   3. Something was actually selected on a "
              *autobead-filter* " layer.")
      "   4. A direction point was actually picked."
      "   5. Every selected object copies successfully. The originals"
      "      are never touched - all work happens on copies."
      "   6. Each copy landed exactly on top of its original. If any"
      "      copy drifted, the run aborts and draws nothing rather"
      "      than leaving geometry in the wrong place."
      "   7. Copies join into continuous chains, so corners can be"
      "      resolved across segment boundaries."
      "   8. Each chain offsets successfully. Any chain that fails is"
      "      counted and reported instead of failing silently."
      "   9. The finished bead is measured back against the chain it"
      "      came from, and the real distance is reported."
      "  10. Temporary geometry is deleted."
      "  11. OSMODE, PEDITACCEPT and CMDECHO are restored."
      ""
      "IF SOMETHING GOES WRONG"
      "  The run is wrapped in a single undo group - one U undoes all"
      "  of it. Pressing Esc mid-run is safe: temporary geometry is"
      "  cleaned up and your settings are restored."
      ""
      "READING THE REPORT"
      "  Every run prints a summary. The two lines worth reading:"
      "    offset asked / offset measured - if these disagree, the"
      "      offset distance is not being applied as requested."
      "    objects picked / joined chains - one closed pool outline"
      "      should collapse to 1 chain. Many chains means the join"
      "      failed; 1 chain from two separate pools means the join"
      "      merged things it should not have."
      ""
      "OTHER COMMANDS"
      "  AUTOBEADVER      - which revision is loaded"
      "  TUTORIALAUTOBEAD - this walkthrough"
      "==========================================================="
      "")))

;; ---- demo mode -------------------------------------------------------------

(defun autobead-demo-layer (name / def)
  ;; Temporary POOL-matching layer for the sample geometry.
  (if (not (tblsearch "LAYER" name))
    (entmake (list '(0 . "LAYER")
                   '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord")
                   (cons 2 name)
                   (cons 70 0)
                   (cons 62 4)               ; cyan
                   (cons 6 "Continuous")))))

(defun autobead-demo-line (a b lay / e)
  ;; Draw one demo segment and return its ename.
  (entmakex (list '(0 . "LINE")
                  (cons 8 lay)
                  (cons 10 a)
                  (cons 11 b))))

(defun autobead-tutorial-demo ( / base lay pts prev ents ss dirpt
                                  x y w h made e )
  (setq lay "POOL-TUTORIAL")

  (autobead-say
    (list ""
          "DEMO MODE"
          "  A sample L-shaped pool will be drawn in your drawing and"
          "  beaded for real, using the same code AUTOBEAD uses."
          "  It goes on a temporary layer and you will be offered a"
          "  cleanup at the end. Undo (U) also removes all of it."))

  (if (null (setq base (getpoint
                         "\nPick an empty spot for the demo pool: ")))
    (progn (prompt "\nDemo cancelled.") (princ))

    (progn
      (autobead-demo-layer lay)
      (setq x (car base)
            y (cadr base))

      ;; L-shaped pool: has convex corners AND one concave corner, so the
      ;; demo shows trimming and extending in the same run.
      (setq pts (list
                  (list x y 0.0)
                  (list (+ x 240.0) y 0.0)
                  (list (+ x 240.0) (+ y 144.0) 0.0)
                  (list (+ x 120.0) (+ y 144.0) 0.0)
                  (list (+ x 120.0) (+ y 240.0) 0.0)
                  (list x (+ y 240.0) 0.0)))

      (setq ents '() prev nil)
      (foreach p pts
        (if prev (setq ents (cons (autobead-demo-line prev p lay) ents)))
        (setq prev p))
      ;; close the loop
      (setq ents (cons (autobead-demo-line prev (car pts) lay) ents))

      (command "._zoom" "_window"
               (list (- x 60.0) (- y 60.0))
               (list (+ x 300.0) (+ y 300.0)))

      (autobead-pause
        (strcat "STEP 1 - the pool\n"
                "      An L-shaped pool outline, 6 separate LINE objects on\n"
                "      layer " lay ". The inside corner is deliberate: it is\n"
                "      where a naive offset would leave a gap."))

      (autobead-pause
        (strcat "STEP 2 - selecting\n"
                "      AUTOBEAD would now ask you to select. Only objects on\n"
                "      a " *autobead-filter* " layer are selectable, so a window "
                "select\n      cannot pick up dimensions, text or hatch by "
                "accident.\n"
                "      Here all 6 lines are selected for you."))

      (setq ss (ssadd))
      (foreach e ents (if (entget e) (ssadd e ss)))

      (autobead-say
        (list "STEP 3 - the direction click"
              "      One click decides which side every bead goes on."
              "      Click INSIDE the pool to bead inward, or outside to"
              "      bead around it."))
      (setq dirpt (getpoint "\n      Click a side to bead toward: "))

      (if (null dirpt)
        (prompt "\nDemo cancelled.")
        (progn
          (autobead-pause
            (strcat "STEP 4 - building the bead\n"
                    "      Copies are made in place, joined into one chain,\n"
                    "      offset " (rtos *autobead-offset*)
                    " toward your click, and moved to the\n"
                    "      \"" *autobead-layer* "\" layer. Watch the corners."))

          (setq made (autobead-build ss dirpt))

          (autobead-say
            (list ""
                  "STEP 5 - the result"
                  (strcat "      " (itoa made) " bead object(s) on \""
                          *autobead-layer* "\".")
                  "      Note what happened at the corners:"
                  "        - outside corners: excess trimmed away"
                  "        - inside corner  : extended to meet, no gap"
                  "      The original pool lines are untouched."
                  ""
                  "      The report above is printed on every real run."
                  "      Compare 'offset asked' with 'offset measured' -"
                  "      they should agree."
                  ""))))

      ;; cleanup
      (initget "Yes No")
      (if (/= "No" (getkword
                     "\nErase the demo pool and its bead? [Yes/No] <Yes>: "))
        (progn
          (foreach e ents (if (entget e) (entdel e)))
          (if (setq ss (ssget "_X" (list (cons 8 *autobead-layer*))))
            (command "._erase" ss ""))
          (prompt "\nDemo geometry erased.")))
      (prompt "\nTutorial complete. Type AUTOBEAD to use it for real.")
      (princ))))

;; ---- entry point -----------------------------------------------------------

(defun c:TUTORIALAUTOBEAD ( / ans )
  (initget "Read Demo Both")
  (setq ans (getkword
              (strcat "\nAUTOBEAD tutorial - read it, or watch a live demo?"
                      "\n  [Read/Demo/Both] <Read>: ")))
  (if (null ans) (setq ans "Read"))
  (if (member ans '("Read" "Both")) (autobead-tutorial-read))
  (if (member ans '("Demo" "Both")) (autobead-tutorial-demo))
  (princ))

;; ---------------------------------------------------------------------------

(prompt (strcat "\nAUTOBEAD " *autobead-rev* " (" *autobead-date* ") loaded."
                "\n  AUTOBEAD          - bead selected pool lines"
                "\n  TUTORIALAUTOBEAD  - how it works"
                "\n  AUTOBEADVER       - revision check"))
(princ)
