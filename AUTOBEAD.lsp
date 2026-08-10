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

(vl-load-com)

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

;; ---- command --------------------------------------------------------------

(defun c:AUTOBEAD ( / *error* beadoff layname layfilt fuzz
                      oldcmd oldos oldpa temps
                      ss dirpt mark copies ss2 chains
                      mark2 news beadcount failcount c e
                      i src dup drift gaps g )

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

     ;; 3) copy the selection in place so the originals are never touched
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
        ;; 4) join the copies into continuous polyline chains
        (setq ss2 (ssadd))
        (foreach c copies (ssadd c ss2))
        (command "._pedit" "_multiple" ss2 "" "_join" fuzz "")
        (autobead-flush)
        (setq chains (autobead-newents mark)
              temps  chains)

        ;; 5) offset each chain toward the click; native offset trims
        ;;    convex corners and extends concave ones automatically
        (setq beadcount 0 failcount 0 gaps '())
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

        ;; 6) report -- including what was actually built, so a bead that
        ;;    lands in the wrong place can be diagnosed from the command line
        (prompt (strcat "\n--- AUTOBEAD ---"
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
                          " farther from the pool line.")))))))

  ;; -- restore --------------------------------------------------------------
  (setvar "PEDITACCEPT" oldpa)
  (setvar "OSMODE" oldos)
  (command "._undo" "_end")
  (setvar "CMDECHO" oldcmd)
  (princ))

(princ "\nAUTOBEAD loaded.  Type AUTOBEAD to run.")
(princ)
