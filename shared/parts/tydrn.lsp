;;; ===================================================================
;;; TYDRN.LSP                                          AutoCAD 2018
;;; -------------------------------------------------------------------
;;; Command: TYDRN
;;;
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
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

(setq *tydrn-version* "v1.0")   ; announced on load; release_lisp.py
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
  (cal:ensure-layer *tydrn-dest-layer* *tydrn-pink*)

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

(princ "\nTYDRN.LSP loaded.  Type TYDRN to run.")
(princ)
