;;; ===================================================================
;;;  XFTCONV.lsp   -  Leica XFT / DXF survey import cleanup
;;;  AutoCAD 2018 (vanilla AutoLISP - no ActiveX, no extra libraries)
;;;
;;;  Command:  XFTCONV
;;;
;;;  What it does, to the objects you highlight:
;;;    1. scales the whole selection by 12 (feet -> inches)
;;;    2. finds every Leica point marker in the selection
;;;         - the X made of 2 crossing LINEs on layer LEICA_POINT
;;;           (a POINT on that layer works too)
;;;         - its name TEXT / MTEXT on layer LEICA_POINT_NAME  ("P22")
;;;    3. replaces each one with an "ab_pt" block on layer POINTS,
;;;       attribute "number" set to the point number with the letter
;;;       prefix stripped ("P22" -> "22")
;;;    4. erases the old marker lines and the old name text
;;;
;;;  Everything else in the selection is just scaled and left alone.
;;;  The whole run is one UNDO step.
;;; ===================================================================
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.


;;; -------------------------------------------------------------------
;;;  SETTINGS - edit these if the export or the template ever changes
;;; -------------------------------------------------------------------

(setq *xft-version* "v1.1") ; printed on load and at command start so a
                             ; support screenshot says which copy is loaded

(setq
  *xft-scale*        12.0                 ; scale factor applied to the selection
  *xft-marker-layer* "LEICA_POINT"        ; layer of the X marker (wildcards ok)
  *xft-name-layer*   "LEICA_POINT_NAME"   ; layer of the point name text
  *xft-block*        "ab_pt"              ; block that replaces the marker
  *xft-block-layer*  "POINTS"             ; layer the block is inserted on
  *xft-att-tag*      "number"             ; attribute tag holding the number
  *xft-att-style*    "Attributes"         ; text style for the attribute
  *xft-att-height*   4.0                  ; attribute height (as shown on the sample)
  *xft-att-offset*   '(0.8697246 -3.5316825) ; attribute offset from the point
  *xft-name-reach*   6.0                  ; name search radius = this x text height
  *xft-fuzz*         1e-4                 ; tolerance for "same point"
)


;;; -------------------------------------------------------------------
;;;  small helpers
;;; -------------------------------------------------------------------

(defun xft:mid (a b)
  (list (/ (+ (car a) (car b)) 2.0)
        (/ (+ (cadr a) (cadr b)) 2.0)
        (/ (+ (caddr a) (caddr b)) 2.0)
  )
)

(defun xft:same (a b)                     ; same location within fuzz
  (< (cal:d2 a b) (* *xft-fuzz* *xft-fuzz*))
)

(defun xft:onlayer (ed pattern)
  (wcmatch (strcase (cdr (assoc 8 ed))) (strcase pattern))
)

;; strip the usual MTEXT formatting codes so "\A1;P22" comes back as "P22"
(defun xft:plain (s / out i c nxt n)
  (setq out "" i 1 n (strlen s))
  (while (<= i n)
    (setq c (substr s i 1))
    (cond
      ((= c "\\")
       (setq nxt (strcase (substr s (1+ i) 1)))
       (cond
         ((member nxt '("P" "X"))                 ; line break / paragraph
          (setq out (strcat out " ") i (+ i 2)))
         ((member nxt '("L" "O" "K"))             ; under/over/strike on-off
          (setq i (+ i 2)))
         ((wcmatch nxt "[ACFHQTW]")               ; codes closed by ";"
          (setq i (+ i 2))
          (while (and (<= i n) (/= (substr s i 1) ";")) (setq i (1+ i)))
          (setq i (1+ i)))
         (t (setq out (strcat out (substr s (1+ i) 1)) i (+ i 2)))
       )
      )
      ((member c '("{" "}")) (setq i (1+ i)))
      (t (setq out (strcat out c) i (1+ i)))
    )
  )
  out
)

;; "P22" -> "22"   "22" -> "22"   "STA" -> "STA"
(defun xft:number (s / i n c)
  (setq s (cal:trim (xft:plain s)) n (strlen s) i 1)
  (while (and (<= i n)
              (setq c (ascii (substr s i 1)))
              (or (< c 48) (> c 57)))
    (setq i (1+ i)))
  (if (<= i n) (substr s i) s)
)

;; where a text entity "sits".  a justified TEXT is really located at its
;; alignment point (11); on MTEXT group 11 is the direction vector, not a
;; point, so MTEXT always uses its insertion point (10).
(defun xft:txtpt (ed)
  (if (and (= "TEXT" (cdr (assoc 0 ed)))
           (assoc 11 ed)
           (or (/= 0 (cdr (assoc 72 (append ed '((72 . 0))))))
               (/= 0 (cdr (assoc 73 (append ed '((73 . 0))))))))
    (cdr (assoc 11 ed))
    (cdr (assoc 10 ed))
  )
)

;; add ename to the marker group at ctr, or start a new group
(defun xft:collect (groups ctr en / out hit)
  (setq out '() hit nil)
  (foreach g groups
    (if (and (not hit) (xft:same (car g) ctr))
      (setq out (cons (cons (car g) (cons en (cdr g))) out) hit t)
      (setq out (cons g out))
    )
  )
  (if hit (reverse out) (cons (list ctr en) groups))
)


;;; -------------------------------------------------------------------
;;;  drawing setup - make sure the layer, style and block are there
;;; -------------------------------------------------------------------

(defun xft:locked (lname / tb)
  (and (setq tb (tblsearch "LAYER" lname))
       (= 4 (logand 4 (cdr (assoc 70 tb)))))
)

(defun xft:style ()
  (if (tblsearch "STYLE" *xft-att-style*)
    *xft-att-style*
    (getvar "TEXTSTYLE")
  )
)

;; build ab_pt the same way the template has it, if it is missing
(defun xft:ensure-block ( / sty)
  (if (not (tblsearch "BLOCK" *xft-block*))
    (progn
      (setq sty (xft:style))
      (entmake (list '(0 . "BLOCK")
                     '(100 . "AcDbEntity")
                     '(8 . "0")
                     '(100 . "AcDbBlockBegin")
                     (cons 2 *xft-block*)
                     '(70 . 2)
                     '(10 0.0 0.0 0.0)
                     (cons 3 *xft-block*)
                     '(1 . "")))
      (entmake '((0 . "POINT")
                 (100 . "AcDbEntity")
                 (8 . "0")
                 (100 . "AcDbPoint")
                 (10 0.0 0.0 0.0)))
      (entmake (list '(0 . "ATTDEF")
                     '(100 . "AcDbEntity")
                     '(8 . "0")
                     '(100 . "AcDbText")
                     '(10 1.0 -2.0 0.0)
                     '(40 . 1.0)
                     '(1 . "0")
                     (cons 7 sty)
                     '(100 . "AcDbAttributeDefinition")
                     '(3 . "Type_Point_Number")
                     (cons 2 *xft-att-tag*)
                     '(70 . 4)))
      (entmake '((0 . "ENDBLK") (100 . "AcDbEntity") (8 . "0") (100 . "AcDbBlockEnd")))
      (princ (strcat "\n  block \"" *xft-block* "\" was not in this drawing - created it."))
    )
  )
  (tblsearch "BLOCK" *xft-block*)
)


;;; -------------------------------------------------------------------
;;;  insert one replacement point
;;; -------------------------------------------------------------------

(defun xft:insert (pt num / apt)
  (setq apt (list (+ (car pt) (car  *xft-att-offset*))
                  (+ (cadr pt) (cadr *xft-att-offset*))
                  (caddr pt)))
  (entmake (list '(0 . "INSERT")
                 '(100 . "AcDbEntity")
                 (cons 8 *xft-block-layer*)
                 '(100 . "AcDbBlockReference")
                 '(66 . 1)
                 (cons 2 *xft-block*)
                 (cons 10 pt)
                 '(41 . 1.0) '(42 . 1.0) '(43 . 1.0)
                 '(50 . 0.0)))
  (entmake (list '(0 . "ATTRIB")
                 '(100 . "AcDbEntity")
                 '(8 . "0")
                 '(100 . "AcDbText")
                 (cons 10 apt)
                 (cons 40 *xft-att-height*)
                 (cons 1 num)
                 (cons 7 (xft:style))
                 '(100 . "AcDbAttribute")
                 (cons 2 *xft-att-tag*)
                 '(70 . 0)))
  (entmake (list '(0 . "SEQEND")
                 '(100 . "AcDbEntity")
                 (cons 8 *xft-block-layer*)))
)


;;; -------------------------------------------------------------------
;;;  XFTCONV
;;; -------------------------------------------------------------------

(defun c:XFTCONV ( / *error* xft:restore oscm osos osclay undone
                     ss base sf i en ed typ
                     markers names g nm e
                     ctr best bestd bestr rank txth d reach num
                     nmade nblank nleft stage done)

  (defun xft:restore ()
    (if oscm   (setvar "CMDECHO" oscm))
    (if osos   (setvar "OSMODE"  osos))
    (if osclay (setvar "CLAYER"  osclay))
  )

  (defun *error* (msg)
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*EXIT*")))
      (princ (strcat "\nXFTCONV error: " msg)))
    (while (> (getvar "CMDACTIVE") 0) (command))   ; back out of SCALE etc.
    (xft:restore)
    (if undone (command "_.UNDO" "_End"))
    (princ "\nNothing was left half done - use U to roll the run back.")
    (princ)
  )

  (setq oscm   (getvar "CMDECHO")
        osos   (getvar "OSMODE")
        osclay (getvar "CLAYER"))

  (princ (strcat "\nXFTCONV " *xft-version*
                 " - scale the survey and swap the Leica points for blocks."))

  ;; ---- selection, scale and base point - staged: Back (or Undo)
  ;; ---- at a later prompt re-opens the previous one ---------------
  (setq stage 1 done nil)
  (while (not done)
    (cond
      ((= stage 1)
       (princ "\nSelect the imported survey objects (Enter = everything in this space): ")
       (setq ss (ssget))
       (if (not ss)
         (setq ss (ssget "_X" (list (cons 410 (getvar "CTAB"))))))
       (if (not ss)
         (setq done 'quit)
         (setq stage 2)))
      ((= stage 2)
       (initget 6 "Back Undo")
       (setq sf (getreal (strcat "\nScale factor <" (rtos *xft-scale* 2 4)
                                 "> [Back]: ")))
       (cond
         ((= (type sf) 'STR) (setq stage 1))
         (T
          (if (not sf) (setq sf *xft-scale*))
          (setq stage 3))))
      (T
       (initget "Back Undo")
       (setq base (getpoint "\nBase point for the scale <0,0> [Back]: "))
       (if (= (type base) 'STR)
         (setq stage 2)
         (progn
           (if (not base) (setq base (list 0.0 0.0 0.0)))
           (setq done T))))))

  (if (eq done 'quit)
    (progn (princ "\nNothing to work on.") (xft:restore) (princ))
    (progn

      ;; ---- locked layers would break the swap --------------------
      (if (or (xft:locked *xft-marker-layer*)
              (xft:locked *xft-name-layer*)
              (xft:locked *xft-block-layer*))
        (progn
          (princ "\nUnlock LEICA_POINT / LEICA_POINT_NAME / POINTS first, then run XFTCONV again.")
          (xft:restore)
          (princ)
        )
        (progn

          (setvar "CMDECHO" 0)
          (setvar "OSMODE" 0)
          (command "_.UNDO" "_BEgin")
          (setq undone t)

          ;; ---- 0. the layer and the block have to be there --------
          (cal:ensure-layer *xft-block-layer* 6)
          (xft:ensure-block)

          ;; ---- 1. scale ------------------------------------------
          (if (/= sf 1.0)
            (progn
              (princ (strcat "\nScaling " (itoa (sslength ss)) " objects by " (rtos sf 2 4) " ..."))
              (command "_.SCALE" ss "" base sf)
            )
          )

          ;; ---- 2. sort the selection into markers and names -------
          (setq markers '() names '() i 0)
          (while (< i (sslength ss))
            (setq en  (ssname ss i)
                  ed  (entget en)
                  typ (cdr (assoc 0 ed)))
            (cond
              ;; name text first - LEICA_POINT would also match its layer
              ((and (member typ '("TEXT" "MTEXT"))
                    (xft:onlayer ed *xft-name-layer*))
               (setq names (cons (list (xft:txtpt ed)
                                       (cdr (assoc 1 ed))
                                       (cdr (assoc 40 ed))
                                       en
                                       nil)
                                 names)))
              ;; the X marker - both lines share the same midpoint
              ((and (= typ "LINE") (xft:onlayer ed *xft-marker-layer*))
               (setq markers (xft:collect markers
                                          (xft:mid (cdr (assoc 10 ed)) (cdr (assoc 11 ed)))
                                          en)))
              ;; some exports drop a plain POINT instead
              ((and (= typ "POINT") (xft:onlayer ed *xft-marker-layer*))
               (setq markers (xft:collect markers (cdr (assoc 10 ed)) en)))
            )
            (setq i (1+ i))
          )

          ;; ---- 3. match each marker to its name ------------------
          ;; the export stacks the name right above the marker, so a
          ;; name in the same column wins over a merely closer one -
          ;; that keeps tight clusters from stealing each other's tags
          (setq nmade 0 nblank 0)
          (foreach g markers
            (setq ctr   (car g)
                  best  nil
                  bestd nil
                  bestr nil)
            (foreach nm names
              (if (not (nth 4 nm))
                (progn
                  (setq txth  (if (and (nth 2 nm) (> (nth 2 nm) 0.0)) (nth 2 nm) 1.0)
                        reach (* *xft-name-reach* txth)
                        d     (cal:d2 ctr (car nm))
                        rank  (if (<= (abs (- (car (car nm)) (car ctr))) (* 0.5 txth)) 0 1))
                  (if (and (< d (* reach reach))
                           (or (not best)
                               (< rank bestr)
                               (and (= rank bestr) (< d bestd))))
                    (setq best nm bestd d bestr rank)
                  )
                )
              )
            )
            (if best
              (progn
                (setq num (xft:number (nth 1 best)))
                (setq names (subst (list (car best) (nth 1 best) (nth 2 best) (nth 3 best) t)
                                   best names))
              )
              (setq num "" nblank (1+ nblank))
            )
            ;; ---- 4. new point in, old marker out ------------------
            (xft:insert ctr num)
            (foreach e (cdr g) (entdel e))
            (if best (entdel (nth 3 best)))
            (setq nmade (1+ nmade))
          )

          ;; names with no marker of their own stay put
          (setq nleft 0)
          (foreach nm names (if (not (nth 4 nm)) (setq nleft (1+ nleft))))

          (command "_.UNDO" "_End")
          (setq undone nil)
          (xft:restore)

          ;; ---- report --------------------------------------------
          (princ (strcat "\n"
                         (itoa nmade) " point(s) replaced with \"" *xft-block* "\"."))
          (if (> nblank 0)
            (princ (strcat "\n" (itoa nblank)
                           " had no name text nearby - inserted with a blank number.")))
          (if (> nleft 0)
            (princ (strcat "\n" (itoa nleft)
                           " name text(s) had no marker - left in the drawing so you can look at them.")))
          (princ)
        )
      )
    )
  )
  (princ)
)


;;; -------------------------------------------------------------------
;;;  make sure the pieces exist as soon as the file loads
;;; -------------------------------------------------------------------

(defun c:XFTCONV-SETUP ()
  (cal:ensure-layer *xft-block-layer* 6)
  (xft:ensure-block)
  (princ (strcat "\nLayer \"" *xft-block-layer* "\" and block \"" *xft-block* "\" are ready."))
  (princ)
)

(princ (strcat "\nXFTCONV.lsp " *xft-version*
               " loaded.  Type XFTCONV to scale a survey import and swap its points."))
(princ)
