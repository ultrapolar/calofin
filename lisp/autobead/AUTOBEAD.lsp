;;; ==========================================================================
;;; AUTOBEAD.lsp
;;; --------------------------------------------------------------------------
;;; Commands:
;;;   AUTOBEAD          - bead the selected POOL lines
;;;   TUTORIALAUTOBEAD  - guided walkthrough (read it, or watch a live demo)
;;;   AUTOBEADVER       - report which version is loaded
;;;
;;; Select POOL lines to "bead" (LINEs, ARCs, and polylines on any POOL*
;;; layer), then click the side to bead toward.  The selection is copied,
;;; joined into continuous chains, and each chain is offset 2" toward the
;;; clicked side using AutoCAD's native offset engine, so corners resolve
;;; automatically:
;;;   - convex (outside) corners have the excess trimmed
;;;   - concave (inside) corners are extended to meet
;;;   - arc / radius corners offset as true concentric arcs
;;;
;;; Step lines - selected lines that cross the pool, touching walls at both
;;; ends - are recognized automatically and always bead full length.
;;;
;;; After the direction click, AUTOBEAD asks whether the side walls are
;;; beaded.  Answer Yes and click each step (tread) that has beaded side
;;; walls: the wall bead is then kept only across those treads' spans, cut
;;; flush at the step lines, and removed everywhere else.  Answer No to
;;; bead every selected wall full length.
;;;
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
;;;   is actually running regardless of which filename they loaded.  The
;;;   filename's REV## is the version below with the dot dropped
;;;   (v0.3 -> REV03).  Regenerate the dated copy with
;;;   python3 tools/release_lisp.py -- do not hand-copy, or the two
;;;   will drift.
;;; ==========================================================================

(vl-load-com)

;; ---- AUTOBEAD SETTINGS ----------------------------------------------------

(setq *autobead-version* "v0.3"      ; revision stamp; the dated twin is
                                     ; named for it (v0.3 -> REV03)
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

;; ---- side-wall geometry helpers -------------------------------------------

(defun autobead-curve-end (e which / p)
  ;; Start or end point of a curve, or nil.  which: 'start or 'end.
  (setq p (vl-catch-all-apply
            (if (eq which 'start)
              'vlax-curve-getStartPoint
              'vlax-curve-getEndPoint)
            (list e)))
  (if (vl-catch-all-error-p p) nil p))

(defun autobead-midpt-of (e / ep len p)
  ;; Point halfway along a curve's length, or nil.
  (setq ep (vl-catch-all-apply 'vlax-curve-getEndParam (list e)))
  (if (vl-catch-all-error-p ep)
    nil
    (progn
      (setq len (vl-catch-all-apply 'vlax-curve-getDistAtParam (list e ep)))
      (if (or (vl-catch-all-error-p len) (null len))
        nil
        (progn
          (setq p (vl-catch-all-apply 'vlax-curve-getPointAtDist
                    (list e (/ len 2.0))))
          (if (or (vl-catch-all-error-p p) (null p)) nil p))))))

(defun autobead-on-other-p (pt chains self / hit cp o)
  ;; T if pt lies on some chain other than self (within drafting slop).
  (setq hit nil)
  (foreach o chains
    (if (and (null hit) (not (eq o self)) (entget o))
      (progn
        (setq cp (vl-catch-all-apply 'vlax-curve-getClosestPointTo
                   (list o pt)))
        (if (and (not (vl-catch-all-error-p cp)) cp
                 (< (distance cp pt) 0.05))
          (setq hit T)))))
  hit)

(defun autobead-sig (pt steps / res a b cr)
  ;; Compartment signature of pt: which side of each step line it is on.
  ;; The step lines cut the pool into compartments (treads); two points with
  ;; equal signatures are in the same compartment.
  (setq res '())
  (foreach s steps
    (setq a  (car s)
          b  (cadr s)
          cr (- (* (- (car b) (car a)) (- (cadr pt) (cadr a)))
                (* (- (cadr b) (cadr a)) (- (car pt) (car a)))))
    (setq res (cons (if (minusp cr) -1 1) res)))
  (reverse res))

(defun autobead-ixpoints (bead step / o1 o2 v a l res)
  ;; WCS points where 'step' (extended to infinity) crosses 'bead'.
  (setq o1 (vlax-ename->vla-object bead)
        o2 (vlax-ename->vla-object step)
        v  (vl-catch-all-apply 'vla-IntersectWith (list o1 o2 2))) ; 2 = acExtendOtherEntity
  (setq res '())
  (if (not (vl-catch-all-error-p v))
    (progn
      (setq a (vl-catch-all-apply 'vlax-variant-value (list v)))
      (if (not (vl-catch-all-error-p a))
        (progn
          (setq l (vl-catch-all-apply 'vlax-safearray->list (list a)))
          (if (vl-catch-all-error-p l) (setq l nil))
          (while (and l (cddr l))               ; flat (x y z x y z ...)
            (setq res (cons (list (car l) (cadr l) 0.0) res)
                  l   (cdddr l))))))
    )
  (reverse res))

(defun autobead-break-at (pieces pt / host cp sp ep mark p)
  ;; Break whichever piece passes through pt (strictly mid-span) at pt.
  ;; Returns the updated piece list; a pt at a piece boundary is a no-op.
  (setq host nil)
  (foreach p pieces
    (if (and (null host) (entget p))
      (progn
        (setq cp (vl-catch-all-apply 'vlax-curve-getClosestPointTo
                   (list p pt))
              sp (autobead-curve-end p 'start)
              ep (autobead-curve-end p 'end))
        (if (and (not (vl-catch-all-error-p cp)) cp
                 (< (distance cp pt) 1e-4)
                 sp (> (distance pt sp) 1e-6)
                 ep (> (distance pt ep) 1e-6))
          (setq host p)))))
  (if host
    (progn
      (setq mark (entlast))
      ;; BREAK takes UCS points; intersections are WCS
      (command "._break" host "_f"
               "_non" (trans pt 0 1) "_non" (trans pt 0 1))
      (autobead-flush)
      (append (vl-remove-if-not '(lambda (x) (entget x)) pieces)
              (autobead-newents mark)))
    pieces))

;; ---- engine ----------------------------------------------------------------
;; Everything that touches the drawing lives here, so AUTOBEAD and the
;; tutorial exercise exactly the same code path.  sidewalls / treadpts come
;; from the side-wall question (treadpts in WCS); pass nil nil to bead every
;; selected wall full length.  Returns the number of bead objects created.

(defun autobead-build (ss dirpt sidewalls treadpts
                       / *error* beadoff layname fuzz
                         oldcmd oldos oldpa temps
                         mark copies ss2 chains mark2 news
                         beadcount failcount c e i src dup drift
                         gaps g sp ep perimchains stepchains steplines
                         perimbeads sigs bps pieces mp kept culled filtered)

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

     ;; 3) classify: a chain whose BOTH endpoints land mid-span on other
     ;;    chains is a step line crossing the pool; the rest are walls
     (setq perimchains '() stepchains '() steplines '())
     (if (> (length chains) 1)
       (foreach c chains
         (setq sp (autobead-curve-end c 'start)
               ep (autobead-curve-end c 'end))
         (if (and sp ep
                  (autobead-on-other-p sp chains c)
                  (autobead-on-other-p ep chains c))
           (setq stepchains (cons c stepchains)
                 steplines  (cons (list sp ep) steplines))
           (setq perimchains (cons c perimchains))))
       (setq perimchains chains))

     ;; 4) offset every chain toward the click; native offset trims
     ;;    convex corners and extends concave ones automatically
     (setq failcount 0 gaps '() perimbeads '())
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
           (if (member c perimchains)
             (setq perimbeads (cons e perimbeads)))
           (setq beadcount (1+ beadcount)))
         (setq failcount (1+ failcount))))

     ;; 5) side walls: keep wall bead only across the clicked treads.
     ;;    Break each wall bead where the step lines cross it, then keep a
     ;;    piece only if its midpoint shares a compartment with a clicked
     ;;    tread point.  Step-face beads are never touched.
     (setq kept 0 culled 0 filtered nil)
     (if (and sidewalls treadpts steplines perimbeads)
       (progn
         (setq filtered T
               sigs (mapcar '(lambda (p) (autobead-sig p steplines))
                            treadpts))
         (foreach e perimbeads
           (setq bps '())
           (foreach c stepchains
             (if (entget c)
               (setq bps (append bps (autobead-ixpoints e c)))))
           (setq pieces (list e))
           (foreach g bps
             (setq pieces (autobead-break-at pieces g)))
           (foreach c pieces
             (if (entget c)
               (progn
                 (setq mp (autobead-midpt-of c))
                 (if (and mp (member (autobead-sig mp steplines) sigs))
                   (setq kept (1+ kept))
                   (progn
                     (entdel c)
                     (setq culled (1+ culled))))))))
         ;; recount: step beads + surviving wall pieces
         (setq beadcount (+ (- beadcount (length perimbeads)) kept))))

     ;; 6) discard the temporary chains
     (foreach c chains
       (if (entget c) (entdel c)))
     (setq temps '())

     ;; 7) report -- including what was actually built, so a bead that
     ;;    lands in the wrong place can be diagnosed from the command line
     (prompt (strcat "\n--- AUTOBEAD " *autobead-version* " ---"
                     "\n  source layers : "
                     (apply 'strcat
                       (mapcar '(lambda (l) (strcat l " "))
                               (autobead-layers ss)))
                     "\n  objects picked: " (itoa (sslength ss))
                     "\n  joined chains : " (itoa (length chains))
                     "  (" (itoa (length perimchains)) " wall, "
                     (itoa (length stepchains)) " step)"
                     "\n  side walls    : "
                     (cond
                       (filtered
                        (strcat "beaded at " (itoa (length treadpts))
                                " clicked step(s) -- kept " (itoa kept)
                                " wall piece(s), removed " (itoa culled)))
                       ((and sidewalls (null steplines))
                        "requested, but no step lines were recognized")
                       (T "full length (not restricted)"))
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

(defun c:AUTOBEAD ( / ss dirpt stage done ans sidewalls treadpts p )
  (autobead-ensure-layer *autobead-layer*)
  ;; staged: Back (or Undo) at any later prompt re-opens the stage before
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
      ((= stage 2)
       (initget "Back Undo")
       (setq dirpt (getpoint "\nClick the side to bead toward [Back]: "))
       (cond
         ((= (type dirpt) 'STR) (setq stage 1))
         ((null dirpt)
          (prompt "\nNo direction point picked.")
          (setq done T))
         (T (setq stage 3))))
      (T
       (initget "Yes No Back Undo")
       (setq ans (getkword
                   "\nAre the side walls beaded? [Yes/No/Back] <No>: "))
       (cond
         ((member ans '("Back" "Undo")) (setq stage 2))
         (T
          (setq sidewalls (= ans "Yes")
                treadpts  '())
          (if sidewalls
            (progn
              (prompt (strcat "\nClick each step (tread) that has beaded"
                              " side walls."))
              (while (setq p (getpoint
                               "\n  Click a step <Enter = done>: "))
                (setq treadpts (cons (trans p 1 0) treadpts)))
              (if (null treadpts)
                (progn
                  (prompt (strcat "\nNo steps clicked - side walls will"
                                  " be beaded full length."))
                  (setq sidewalls nil)))))
          (autobead-build ss dirpt sidewalls treadpts)
          (setq done T))))))
  (princ))

;; ---- AUTOBEADVER -----------------------------------------------------------

(defun c:AUTOBEADVER ()
  (prompt (strcat "\nAUTOBEAD " *autobead-version*
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
      (strcat " AUTOBEAD " *autobead-version* " - how it works")
      "==========================================================="
      ""
      "WHAT IT DOES"
      "  Draws a bead line at a fixed offset from your pool edge,"
      (strcat "  on the \"" *autobead-layer* "\" layer. Corners are resolved for")
      "  you: outside corners get trimmed, inside corners get"
      "  extended to meet, and radius corners stay concentric."
      "  Lines that cross the pool touching walls at both ends are"
      "  recognized as STEP lines and always bead full length."
      ""
      "USING IT"
      "  1. Type AUTOBEAD."
      (strcat "  2. Select your pool lines. Only objects on a "
              *autobead-filter* " layer")
      "     can be picked, so a window select is safe - dimensions,"
      "     text and hatch are ignored."
      "  3. Click the side you want the bead on. One click sets the"
      "     direction for everything you selected."
      "  4. Answer: are the side walls beaded?"
      "       No  - every selected wall beads full length."
      "       Yes - click each step (tread) that has beaded side"
      "             walls, then Enter. The wall bead is kept only"
      "             across those treads, cut flush at the step"
      "             lines, and removed everywhere else. Step-face"
      "             beads always draw either way."
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
      "   8. Chains are classified into walls and step lines, and"
      "      the split is printed in the report."
      "   9. Each chain offsets successfully. Any chain that fails is"
      "      counted and reported instead of failing silently."
      "  10. With beaded side walls, wall bead outside the clicked"
      "      treads is removed, and the kept/removed counts are"
      "      reported."
      "  11. The finished bead is measured back against the chain it"
      "      came from, and the real distance is reported."
      "  12. Temporary geometry is deleted."
      "  13. OSMODE, PEDITACCEPT and CMDECHO are restored."
      ""
      "IF SOMETHING GOES WRONG"
      "  The run is wrapped in a single undo group - one U undoes all"
      "  of it. Pressing Esc mid-run is safe: temporary geometry is"
      "  cleaned up and your settings are restored."
      ""
      "READING THE REPORT"
      "  Every run prints a summary. The lines worth reading:"
      "    offset asked / offset measured - if these disagree, the"
      "      offset distance is not being applied as requested."
      "    joined chains (wall, step) - check the tool recognized"
      "      your step lines; a step counted as a wall will bead"
      "      full length and drag wall bead with it."
      "    side walls - confirms which treads were honored and how"
      "      many wall pieces were kept vs removed."
      ""
      "OTHER COMMANDS"
      "  AUTOBEADVER      - which version is loaded"
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
                                  x y made e )
  (setq lay "POOL-TUTORIAL")

  (autobead-say
    (list ""
          "DEMO MODE"
          "  A sample pool with two step lines will be drawn in your"
          "  drawing and beaded for real, using the same code AUTOBEAD"
          "  uses. It goes on a temporary layer and you will be offered"
          "  a cleanup at the end. Undo (U) also removes all of it."))

  (if (null (setq base (getpoint
                         "\nPick an empty spot for the demo pool: ")))
    (progn (prompt "\nDemo cancelled.") (princ))

    (progn
      (autobead-demo-layer lay)
      (setq x (car base)
            y (cadr base))

      ;; open-ended pool run: bottom wall, end wall, top wall, plus two
      ;; step lines crossing the pool near the end wall
      (setq ents
        (list
          (autobead-demo-line (list x y 0.0)
                              (list (+ x 300.0) y 0.0) lay)
          (autobead-demo-line (list (+ x 300.0) y 0.0)
                              (list (+ x 300.0) (+ y 144.0) 0.0) lay)
          (autobead-demo-line (list (+ x 300.0) (+ y 144.0) 0.0)
                              (list x (+ y 144.0) 0.0) lay)
          ;; step lines at 66" and 90" from the end wall
          (autobead-demo-line (list (+ x 234.0) y 0.0)
                              (list (+ x 234.0) (+ y 144.0) 0.0) lay)
          (autobead-demo-line (list (+ x 210.0) y 0.0)
                              (list (+ x 210.0) (+ y 144.0) 0.0) lay)))

      (command "._zoom" "_window"
               (list (- x 60.0) (- y 60.0))
               (list (+ x 360.0) (+ y 204.0)))

      (autobead-pause
        (strcat "STEP 1 - the pool\n"
                "      A pool run on layer " lay ": bottom wall, end wall,\n"
                "      top wall, and two step lines crossing the pool near\n"
                "      the end. The step lines touch the walls at both"
                " ends,\n      which is how AUTOBEAD recognizes them as"
                " steps."))

      (autobead-pause
        (strcat "STEP 2 - selecting\n"
                "      AUTOBEAD would now ask you to select. Only objects"
                " on\n      a " *autobead-filter* " layer are selectable,"
                " so a window select\n      cannot pick up dimensions,"
                " text or hatch by accident.\n"
                "      Here all 5 lines are selected for you."))

      (setq ss (ssadd))
      (foreach e ents (if (entget e) (ssadd e ss)))

      (autobead-say
        (list "STEP 3 - the direction click"
              "      One click decides which side every bead goes on."
              "      Click INSIDE the pool (between the walls)."))
      (setq dirpt (getpoint "\n      Click a side to bead toward: "))

      (if (null dirpt)
        (prompt "\nDemo cancelled.")
        (progn
          (autobead-pause
            (strcat "STEP 4 - the side-wall question\n"
                    "      AUTOBEAD would now ask: are the side walls"
                    " beaded?\n"
                    "      For this demo the answer is Yes, with the top"
                    " step\n      (between the end wall and the first"
                    " step line)\n      clicked as the beaded one - so"
                    " wall bead survives\n      only across that tread."))

          (setq made (autobead-build ss dirpt T
                       (list (list (+ x 267.0) (+ y 72.0) 0.0))))

          (autobead-say
            (list ""
                  "STEP 5 - the result"
                  (strcat "      " (itoa made) " bead object(s) on \""
                          *autobead-layer* "\".")
                  "      Note what happened:"
                  "        - both step lines got full-length beads"
                  "        - wall bead survives only around the top"
                  "          tread, cut flush at the first step line"
                  "        - the rest of the walls have no bead"
                  ""
                  "      The report above is printed on every real run."
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

(prompt (strcat "\nAUTOBEAD " *autobead-version* " loaded."
                "\n  AUTOBEAD          - bead selected pool lines"
                "\n  TUTORIALAUTOBEAD  - how it works"
                "\n  AUTOBEADVER       - version check"))
(princ)
