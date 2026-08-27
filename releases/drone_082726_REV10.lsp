;;; ===================================================================
;;; DRONE.LSP                                          AutoCAD 2018
;;; -------------------------------------------------------------------
;;; Command: DRONE
;;;
;;; Drawing cleanup routine that applies five fixes in one pass:
;;;
;;;   1. TEXT  - every highlighted (pre-selected) text entity is
;;;              switched to style ROMANC at height 4.5, with color,
;;;              linetype and lineweight forced to BYLAYER.
;;;              If nothing is highlighted when the command starts you
;;;              are prompted to select text; pressing Enter at that
;;;              prompt processes ALL text in the drawing.
;;;
;;;   2. POOL / SPA POINTS - every POINT entity on layer POOL or on
;;;              layer SPA is moved to layer POINTS with color /
;;;              linetype / lineweight all set to BYLAYER (POINTS is
;;;              magenta, so they show pink).  The pool's points and
;;;              the spa's share the one POINTS layer.
;;;
;;;   3. SPA PERIMETER - the spa outline - lines, arcs, circles,
;;;              ellipses, polylines and splines on layer SPA - is
;;;              moved to layer POOL, so the pool perimeter and the
;;;              spa perimeter share it, and forced to BYLAYER so the
;;;              moved geometry picks up POOL's own appearance.
;;;              Points are swept off SPA by step 2 first, so only
;;;              the outline is left to move.
;;;
;;;   4. ANCHOR POINTS - every POINT entity on layer ANCHORS is given
;;;              an explicit magenta (ACI 6) color - the same pink as
;;;              the points - but stays on the ANCHORS layer.
;;;
;;;   5. ORIENT - after the conversion the processed text is rotated
;;;              flat so it reads west -> east, right side up
;;;              (absolute angle 0).  Each text pivots about its own
;;;              insertion point - the labels share that point in
;;;              space with the POINT they belong to - so every label
;;;              stays anchored to its point.  Set
;;;              *drone-orient-angle* to nil to only flip upside-down
;;;              text instead ("Most readable").
;;;
;;; The ROMANC text style and the POINTS and POOL layers are created
;;; if they do not already exist.  Locked layers are unlocked for the
;;; duration of the command and re-locked afterwards.  The whole run
;;; is wrapped in a single undo group.
;;; ===================================================================

(setq *drone-version* "v1.0")   ; announced on load; release_lisp.py
                                   ; stamps the dated twin in releases/

(vl-load-com)

;; ---------------------------------------------------------------
;; Configuration
;; ---------------------------------------------------------------
(setq *drone-text-style*  "ROMANC"
      *drone-text-font*   "romanc.shx"
      *drone-text-height* 4.5
      *drone-pt-layers*   '("POOL" "SPA")   ; POINTs found on these...
      *drone-dest-layer*  "POINTS"          ; ...move to this one
      *drone-perim-src*   '("SPA")          ; outlines found on these...
      *drone-perim-layer* "POOL"            ; ...move to this one
      *drone-perim-types* "LINE,ARC,CIRCLE,ELLIPSE,LWPOLYLINE,POLYLINE,SPLINE"
      *drone-perim-color* 4          ; ACI 4 = cyan, POOL's own color
      *drone-anch-layer*  "ANCHORS"
      *drone-pink*        6           ; ACI 6 = magenta / pink
      *drone-orient-angle* 0.0)       ; absolute text angle in degrees
                                      ; (0 = read west->east, right
                                      ; side up); nil = only flip
                                      ; upside-down text ("Most
                                      ; readable")

;; ---------------------------------------------------------------
;; Helpers
;; ---------------------------------------------------------------

;; Make sure the target text style exists.
(defun drone:ensure-style (name font)
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
(defun drone:ensure-layer (name color)
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
(defun drone:unlock-layers (names doc / layers obj unlocked name)
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

(defun drone:relock-layers (objs / obj)
  (foreach obj objs (vla-put-Lock obj :vlax-true)))

;; Reset color / linetype / lineweight of a vla-object to BYLAYER.
(defun drone:force-bylayer (obj)
  (vla-put-Color obj acByLayer)
  (vla-put-Linetype obj "ByLayer")
  (vla-put-Lineweight obj acLnWtByLayer))

;; Rotate a text to the target orientation.  Setting the Rotation
;; property pivots the text about its insertion/alignment point; the
;; point labels share that point in space with the POINT entity they
;; belong to, so each label swings around its own point and stays
;; anchored to it.  With *drone-orient-angle* set, the text is turned
;; to that absolute angle; with it nil, only upside-down text (angle
;; in (90, 270] degrees) is flipped 180.
(defun drone:orient (obj / cur target)
  (setq cur (rem (vla-get-Rotation obj) (* 2.0 pi)))   ; radians
  (if (< cur 0.0) (setq cur (+ cur (* 2.0 pi))))
  (setq target
        (if *drone-orient-angle*
          (* pi (/ *drone-orient-angle* 180.0))
          (if (and (> cur (* 0.5 pi)) (<= cur (* 1.5 pi)))
            (rem (+ cur pi) (* 2.0 pi))
            cur)))
  (if (not (equal cur target 1e-8))
    (vla-put-Rotation obj target)))

;; Join layer names into the comma-separated form an ssget filter
;; wants: ("POOL" "SPA") -> "POOL,SPA".
(defun drone:csv (names / out name)
  (foreach name names
    (setq out (if out (strcat out "," name) name)))
  out)

;; Collect the distinct layer names used by the entities of a
;; selection set.
(defun drone:sel-layers (ss / i lay result)
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
(defun drone:error (msg)
  (if *drone-unlocked* (drone:relock-layers *drone-unlocked*))
  (setq *drone-unlocked* nil)
  (if *drone-doc* (vla-EndUndoMark *drone-doc*))
  (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
    (princ (strcat "\nDRONE error: " msg)))
  (if *drone-old-error* (setq *error* *drone-old-error*))
  (princ))

;; ---------------------------------------------------------------
;; Main command
;; ---------------------------------------------------------------
(defun c:DRONE (/ ss-text ss-pt ss-perim ss-anch i ent obj
                  n-text n-pt n-perim n-anch)

  (setq *drone-old-error* *error*
        *error*           drone:error
        *drone-doc*       (vla-get-ActiveDocument (vlax-get-acad-object))
        *drone-unlocked*  nil
        n-text 0  n-pt 0  n-perim 0  n-anch 0)

  (vla-StartUndoMark *drone-doc*)

  ;; Make sure the style and both destination layers are available.
  (drone:ensure-style *drone-text-style* *drone-text-font*)
  (drone:ensure-layer *drone-dest-layer* *drone-pink*)
  (drone:ensure-layer *drone-perim-layer* *drone-perim-color*)

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
  ;; 2/3/4. Points on POOL / SPA, the spa outline, and the ANCHORS
  ;;        points - anywhere in the drawing
  ;; ------------------------------------------------------------
  (setq ss-pt    (ssget "_X" (list '(0 . "POINT")
                                   (cons 8 (drone:csv *drone-pt-layers*))))
        ss-perim (ssget "_X" (list (cons 0 *drone-perim-types*)
                                   (cons 8 (drone:csv *drone-perim-src*))))
        ss-anch  (ssget "_X" (list '(0 . "POINT")
                                   (cons 8 *drone-anch-layer*))))

  ;; Unlock every layer we are about to touch.
  (setq *drone-unlocked*
        (drone:unlock-layers
          (append *drone-pt-layers*
                  *drone-perim-src*
                  (list *drone-perim-layer*
                        *drone-anch-layer*
                        *drone-dest-layer*)
                  (drone:sel-layers ss-text))
          *drone-doc*))

  ;; Text -> ROMANC / 4.5 / BYLAYER
  (if ss-text
    (progn
      (setq i 0)
      (while (< i (sslength ss-text))
        (setq ent (ssname ss-text i)
              obj (vlax-ename->vla-object ent))
        (vla-put-StyleName obj *drone-text-style*)
        (vla-put-Height obj *drone-text-height*)
        (drone:force-bylayer obj)
        (setq n-text (1+ n-text)
              i      (1+ i)))))

  ;; POOL / SPA points -> POINTS layer, everything BYLAYER
  (if ss-pt
    (progn
      (setq i 0)
      (while (< i (sslength ss-pt))
        (setq obj (vlax-ename->vla-object (ssname ss-pt i)))
        (vla-put-Layer obj *drone-dest-layer*)
        (drone:force-bylayer obj)
        (setq n-pt (1+ n-pt)
              i    (1+ i)))))

  ;; Spa outline -> POOL layer, everything BYLAYER so it takes POOL's
  ;; color and linetype rather than carrying the spa layer's over.
  (if ss-perim
    (progn
      (setq i 0)
      (while (< i (sslength ss-perim))
        (setq obj (vlax-ename->vla-object (ssname ss-perim i)))
        (vla-put-Layer obj *drone-perim-layer*)
        (drone:force-bylayer obj)
        (setq n-perim (1+ n-perim)
              i       (1+ i)))))

  ;; ANCHORS points -> pink (ACI 6), same layer
  (if ss-anch
    (progn
      (setq i 0)
      (while (< i (sslength ss-anch))
        (setq obj (vlax-ename->vla-object (ssname ss-anch i)))
        (vla-put-Color obj *drone-pink*)
        (setq n-anch (1+ n-anch)
              i      (1+ i)))))

  ;; ------------------------------------------------------------
  ;; 5. Orient the converted text to read west -> east, right side
  ;;    up, each label pivoting about its insertion point (= the
  ;;    point it labels).
  ;; ------------------------------------------------------------
  (if ss-text
    (progn
      (setq i 0)
      (while (< i (sslength ss-text))
        (vl-catch-all-apply
          'drone:orient
          (list (vlax-ename->vla-object (ssname ss-text i))))
        (setq i (1+ i)))))

  ;; Re-lock whatever we unlocked and close the undo group.
  (drone:relock-layers *drone-unlocked*)
  (setq *drone-unlocked* nil)
  (vla-EndUndoMark *drone-doc*)
  (setq *error* *drone-old-error*)

  (princ (strcat "\nDRONE done: "
                 (itoa n-text) " text -> " *drone-text-style*
                 " h" (rtos *drone-text-height* 2 2)
                 " oriented W->E, "
                 (itoa n-pt) " point(s) -> " *drone-dest-layer*
                 ", "
                 (itoa n-perim) " perimeter -> " *drone-perim-layer*
                 ", "
                 (itoa n-anch) " ANCHORS point(s) -> pink."))
  (princ))

(princ "\nDRONE.LSP loaded.  Type DRONE to run.")
(princ)
