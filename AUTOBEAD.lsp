;;; ==========================================================================
;;; AUTOBEAD.lsp
;;; --------------------------------------------------------------------------
;;; Command:  AUTOBEAD
;;;
;;; Prompts the user to select POOL lines to "bead" (LINEs, ARCs, and
;;; polylines on any POOL* layer), then to click the side to bead toward.
;;; The selection is copied, joined into continuous chains, and each chain
;;; is offset 2" toward the clicked side using AutoCAD's native offset
;;; engine, so corners come out right automatically:
;;;   - convex (outside) corners have the excess trimmed
;;;   - concave (inside) corners are extended to meet
;;;   - arc / radius corners offset as true concentric arcs
;;; The finished beads land on the "Bead Track" layer.  The original pool
;;; geometry is never modified, and the whole operation undoes with one U.
;;;
;;; Tunables (top of c:AUTOBEAD):
;;;   beadoff  - offset distance, drawing units (2.0 = 2 inches)
;;;   layname  - output layer name ("Bead Track")
;;;   layfilt  - selection layer filter ("POOL*")
;;;   fuzz     - join tolerance for near-touching endpoints (0.001)
;;; ==========================================================================

;; ---- helpers --------------------------------------------------------------

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

;; ---- command --------------------------------------------------------------

(defun c:AUTOBEAD ( / *error* beadoff layname layfilt fuzz
                      oldcmd oldos oldpa temps
                      ss dirpt mark copies ss2 chains
                      mark2 news beadcount failcount c e )

  (setq beadoff 2.0                ; bead offset distance (2")
        layname "Bead Track"       ; output layer
        layfilt "POOL*"            ; selectable source layers
        fuzz    0.001)             ; endpoint join tolerance

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
        temps '())

  (autobead-ensure-layer layname)

  ;; 1) select the pool geometry (filtered to POOL* layers)
  (prompt (strcat "\nSelect POOL lines to bead (layers " layfilt "): "))
  (setq ss (ssget (list '(0 . "LINE,ARC,LWPOLYLINE,POLYLINE")
                        (cons 8 layfilt))))

  (cond
    ((null ss)
     (prompt (strcat "\nNothing selected on a " layfilt " layer.")))

    ;; 2) pick the side to bead toward
    ((null (setq dirpt (getpoint "\nClick the side to bead toward: ")))
     (prompt "\nNo direction point picked."))

    (T
     (setvar "OSMODE" 0)          ; keep osnaps out of the internal commands
     (setvar "PEDITACCEPT" 1)     ; auto-accept line/arc -> pline conversion

     ;; 3) copy the selection so the originals are never touched
     (setq mark (entlast))
     (command "._copy" ss "" "_displacement" "_non" '(0.0 0.0 0.0))
     (autobead-flush)
     (setq copies (autobead-newents mark)
           temps  copies)

     (cond
       ((null copies)
        (prompt "\nCould not copy the selection (locked source layer?)."))

       (T
        ;; 4) join the copies into continuous polyline chains
        (setq ss2 (ssadd))
        (foreach c copies (ssadd c ss2))
        (command "._pedit" "_multiple" ss2 "" "_join" fuzz "")
        (autobead-flush)
        (setq chains (autobead-newents mark)
              temps  chains)

        ;; 5) offset each chain toward the click; native offset trims
        ;;    convex corners and extends concave ones automatically
        (setq beadcount 0 failcount 0)
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
              (setq beadcount (1+ beadcount)))
            (setq failcount (1+ failcount)))
          ;; discard the temporary chain
          (if (entget c) (entdel c)))
        (setq temps '())

        ;; 6) report
        (prompt (strcat "\nCreated " (itoa beadcount)
                        " bead object(s) on " layname "."))
        (if (> failcount 0)
          (prompt (strcat "\n" (itoa failcount)
                          " chain(s) could not be offset -- try clicking"
                          " farther from the pool line.")))))))

  ;; -- restore --------------------------------------------------------------
  (setvar "PEDITACCEPT" oldpa)
  (setvar "OSMODE" oldos)
  (command "._undo" "_end")
  (setvar "CMDECHO" oldcmd)
  (princ))

(princ "\nAUTOBEAD loaded.  Type AUTOBEAD to run.")
(princ)
