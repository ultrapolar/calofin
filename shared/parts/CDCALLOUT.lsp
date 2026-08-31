;;; ===================================================================
;;; CDCALLOUT.lsp  --  cross-dimension from Pt.## to Pt.## by number
;;; -------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP; needs the Visual LISP
;;; engine that ships with full AutoCAD -- LT cannot run this).
;;;
;;; Command:  CDCALLOUT
;;;
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;
;;; The dimensioning sister of BPCALLOUT.  Instead of clicking points,
;;; you name them: type the FROM point number and the TO point number,
;;; and an aligned dimension is drawn between those two survey points
;;; -- the dimension line sitting right inbetween, on the tie itself,
;;; exactly where CDCREATE puts its (nudge cdo:*offset* to push it
;;; off) -- in the "CROSS DIMENSIONS" dimension style, on the
;;; "DIMENSION" layer, ByLayer, the same convention CDCREATE and POOL
;;; use.  Rinse and repeat: it keeps asking for the next FROM number
;;; until you press Enter.  Nothing is ever clicked.
;;;
;;; Point numbers are typed the way they read in the drawing: "35",
;;; "Pt.35", "pt 35", "#35" and "035" all name the same point -- the
;;; number is matched against the "number" attribute on the survey
;;; point blocks (the same classifier BPCALLOUT and LHD use: an
;;; "ab_pt" INSERT on any layer, any other INSERT on the POINTS
;;; layer, or a plain POINT on the POINTS layer).
;;;
;;; A number that names no point in the drawing is reported and the
;;; prompt re-asks -- nothing is drawn from a typo.  Enter at the TO
;;; prompt cancels just that round.  The whole run is one undo group:
;;; a single U takes every dimension away.
;;;
;;; Going back a step follows the shared Back convention (see the root
;;; README): B/BACK/U/UNDO at the TO prompt re-asks FROM, and Back at
;;; the FROM prompt (offered once something is drawn) un-draws the
;;; last dimension.
;;;
;;; A missing "CROSS DIMENSIONS" style is NOT invented: the dims are
;;; drawn in whatever style is current and the routine says so, so a
;;; drawing started from the wrong template is obvious instead of
;;; silently producing wrong-looking dims (CDCREATE's rule, kept).
;;;
;;; Versioning: see tools/release_lisp.py at the repo root.  It reads
;;; *cdcallout-version* below and stamps a dated, REV-numbered twin of
;;; this file into releases/.
;;; ===================================================================

;; ---- configuration -------------------------------------------------
(setq *cdcallout-version* "v1.4")   ; announced on load; release_lisp.py
                                    ; reads this banner and stamps the
                                    ; dated twin in releases/ from it
(setq cdo:*style*       "CROSS DIMENSIONS") ; dimension style to use
(setq cdo:*layer*       "DIMENSION")        ; layer the dims land on
(setq cdo:*offset*      0.0)        ; distance the dimension line is
                                    ; pushed off the tie it measures,
                                    ; drawing units (0.0 = right
                                    ; inbetween, on the tie itself --
                                    ; CDCREATE's convention)
(setq *CDO-POINT-BLOCK* "ab_pt")    ; block name whose INSERTs mark
                                    ; points wherever they sit
(setq *CDO-POINT-LAYER* "POINTS")   ; layer whose POINTs/INSERTs are
                                    ; always points
(setq *CDO-PT-TAG*      "number")   ; attribute tag on the point block
                                    ; naming the point, as in "Pt.17"

;; ---- point lookup --------------------------------------------------

;; Every NAMED survey point in the drawing, as ((x y z) . name) pairs.
;; What counts as a point matches BPCALLOUT/LHD; a point whose number
;; cannot be read is left out -- it cannot be asked for by name.
(defun cdo:collect-points (/ ss i en ed typ p nm out)
  (setq out nil
        ss  (ssget "_X" '((0 . "INSERT"))))
  (if ss
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq en (ssname ss i)
              ed (entget en)
              p  (cdr (assoc 10 ed)))
        (if (or (= (strcase (cdr (assoc 2 ed)))
                   (strcase *CDO-POINT-BLOCK*))
                (= (strcase (cdr (assoc 8 ed)))
                   (strcase *CDO-POINT-LAYER*)))
          (progn
            (setq nm (cal:block-number en *CDO-PT-TAG*))
            (if (and nm (/= nm ""))
              (setq out (cons (cons (list (car p) (cadr p) 0.0) nm)
                              out)))))
        (setq i (1+ i)))))
  (reverse out))

;; One comparable form for a point number, so "35", "Pt.35", "pt 35",
;; "#35" and "035" all meet in the middle: uppercase, spaces and
;; hashes dropped, a leading "PT" / "PT." dropped, and a value that
;; reads as a number rendered numerically (so leading zeros don't
;; matter).  Only the dot right after PT is a prefix dot - a point
;; genuinely named "40.5" keeps its decimal.
(defun cdo:canon (s / out i ch)
  (setq s (strcase s) out "" i 1)
  (while (<= i (strlen s))
    (setq ch (substr s i 1))
    (if (not (member ch '(" " "#")))
      (setq out (strcat out ch)))
    (setq i (1+ i)))
  (if (and (>= (strlen out) 2) (= (substr out 1 2) "PT"))
    (progn
      (setq out (substr out 3))
      (if (= (substr out 1 1) ".") (setq out (substr out 2)))))
  (if (distof out 2)
    (rtos (distof out 2) 2 8)
    out))

;; The survey point the typed number names, or nil.  The first match
;; wins when a drawing carries the same number twice.
(defun cdo:find-point (s cands / want found c)
  (setq want (cdo:canon s) found nil)
  (foreach c cands
    (if (and (null found) (= (cdo:canon (cdr c)) want))
      (setq found c)))
  found)

;; ---- dimension helpers (CDCREATE's conventions, kept) --------------

;; midpoint of p1->p2, pushed perpendicular to the tie by dist
;; (dist 0.0 puts the dimension line straight inbetween, on the tie)
(defun cdo:loc (p1 p2 dist / dx dy d m)
  (setq m (list (* 0.5 (+ (car  p1) (car  p2)))
                (* 0.5 (+ (cadr p1) (cadr p2)))
                (* 0.5 (+ (caddr p1) (caddr p2)))))
  (if (equal dist 0.0 1e-12)
    m
    (progn
      (setq dx (- (car  p2) (car  p1))
            dy (- (cadr p2) (cadr p1))
            d  (sqrt (+ (* dx dx) (* dy dy))))
      (if (> d 1e-9)
        (list (+ (car  m) (* dist (/ (- dy) d)))
              (+ (cadr m) (* dist (/ dx d)))
              (caddr m))
        m))))

;; make a layer current, creating it first when the drawing lacks it
(defun cdo:setlayer (name)
  (if (not (tblsearch "LAYER" name))
    (entmake (list '(0 . "LAYER")
                   '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord")
                   (cons 2 name)
                   '(70 . 0)
                   '(62 . 7)
                   '(6 . "Continuous"))))
  (setvar "CLAYER" name))

;; restore a dimension style by name when the drawing has it;
;; returns T when the style was set
(defun cdo:setstyle (name)
  (if (and name (tblsearch "DIMSTYLE" name))
    (progn (command "_.-DIMSTYLE" "_Restore" name) t)))

;; a copy of an entget list with every entry for group CODE dropped
(defun cdo:strip (code lst / out g)
  (foreach g lst (if (/= code (car g)) (setq out (cons g out))))
  (reverse out))

;; force a freshly drawn dimension onto the layer and style CDCALLOUT
;; promises, ByLayer -- DIMLAYER, a style-owned layer or a leftover
;; per-entity override would otherwise have the last word
(defun cdo:fixdim (en havestyle / ed code)
  (if (and en (setq ed (entget en))
           (= "DIMENSION" (cdr (assoc 0 ed))))
    (progn
      (setq ed (if (assoc 8 ed)
                 (subst (cons 8 cdo:*layer*) (assoc 8 ed) ed)
                 (append ed (list (cons 8 cdo:*layer*)))))
      (if havestyle
        (setq ed (if (assoc 3 ed)
                   (subst (cons 3 cdo:*style*) (assoc 3 ed) ed)
                   (append ed (list (cons 3 cdo:*style*))))))
      (foreach code '(62 6 370) (setq ed (cdo:strip code ed)))
      (entmod ed)
      (entupd en)
      t)))

;; ---- the command ---------------------------------------------------
;; NOTE: no local here may be named after a function this routine
;; calls - an AutoLISP local SHADOWS the function of the same name for
;; the whole call (the BPCALLOUT v1.0 lesson).
(defun c:CDCALLOUT (/ *error* olderr oce ocl oos odim grouped havestyle
                      cands s1 s2 a b pre new made d dimlist stage
                      done)

  ;; -- restore drawing state on error / Esc.  A dimension command may
  ;;    still be open, so talk to AutoCAD through command-s -- and close
  ;;    the undo group, or the next U would swallow the user's own work
  (setq olderr *error*)
  (defun *error* (m)
    (if (and odim (not (equal odim (getvar "DIMSTYLE"))))
      (vl-catch-all-apply 'command-s (list "_.-DIMSTYLE" "_Restore" odim)))
    (if ocl (setvar "CLAYER"  ocl))
    (if oos (setvar "OSMODE"  oos))
    (if oce (setvar "CMDECHO" oce))
    (if grouped (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (setq *error* olderr)
    (if (and m (not (wcmatch (strcase m) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\n** Error: " m)))
    (princ))

  (vl-load-com)
  (setq oce  (getvar "CMDECHO")
        ocl  (getvar "CLAYER")
        oos  (getvar "OSMODE")
        odim (getvar "DIMSTYLE"))

  (princ (strcat "\nCDCALLOUT " *cdcallout-version*))
  (setq cands (cdo:collect-points))
  (if (null cands)
    (princ "\nNo named survey points found in the drawing -- nothing to dimension between.")
    (progn
      (princ (strcat "\n" (itoa (length cands)) " named survey point(s)"
                     " found.  Type numbers as they read in the"
                     " drawing (\"35\" or \"Pt.35\")."))
      (setvar "CMDECHO" 0)
      (setvar "OSMODE"  0)
      (command "_.UNDO" "_Begin")
      (setq grouped t)
      (cdo:setlayer cdo:*layer*)
      (setq havestyle (cdo:setstyle cdo:*style*))
      (if (not havestyle)
        (princ (strcat "\n** This drawing has no \"" cdo:*style*
                       "\" dimension style -- dims drawn in \""
                       (getvar "DIMSTYLE")
                       "\" instead.  Create the style (or start"
                       " from the standard template) and re-run.")))

      ;; -- the rinse-repeat loop, as two stages so Back can re-ask
      ;;    the previous question: FROM -> TO, per the shared Back
      ;;    convention.  B/BACK/U/UNDO at TO re-asks FROM; Back at
      ;;    FROM (offered once something is drawn) un-draws the last
      ;;    dimension.  The dimension line goes right inbetween the
      ;;    two points -- nothing to pick.
      (setq made 0 dimlist nil stage 1 done nil)
      (while (not done)
        (cond
          ;; -- FROM: the loop head
          ((= stage 1)
           (setq s1 (getstring
                      (if dimlist
                        "\nFrom point number (Enter when done) [Back]: "
                        "\nFrom point number (Enter when done): ")))
           (cond
             ((= s1 "") (setq done t))
             ((cal:back-word-p s1)
              (if dimlist
                (progn
                  (entdel (car dimlist))
                  (setq dimlist (cdr dimlist)
                        made    (1- made))
                  (princ "\nStepping back one dimension."))
                (princ "\nAlready at the first dimension.")))
             ((null (setq a (cdo:find-point s1 cands)))
              (princ (strcat "\n  No point numbered \"" s1
                             "\" in the drawing -- nothing drawn.")))
             (t (setq stage 2))))
          ;; -- TO: a good answer draws the dimension right away
          (t
           (setq s2 (getstring (strcat "\nTo point number (from Pt."
                                       (cdr a) ") [Back]: ")))
           (cond
             ((= s2 "")
              (princ "\n  No second point -- this one skipped.")
              (setq stage 1))
             ((cal:back-word-p s2) (setq stage 1))
             ((null (setq b (cdo:find-point s2 cands)))
              (princ (strcat "\n  No point numbered \"" s2
                             "\" in the drawing -- nothing drawn.")))
             ((< (distance (car a) (car b)) 1e-9)
              (princ (strcat "\n  Pt." (cdr a) " and Pt." (cdr b)
                             " sit on the same spot -- nothing to"
                             " measure.")))
             (t
              (setq pre (entlast))
              (command "_.DIMALIGNED"
                       "_non" (trans (car a) 0 1)
                       "_non" (trans (car b) 0 1)
                       "_non" (trans (cdo:loc (car a) (car b)
                                              cdo:*offset*) 0 1))
              (setq new (entlast))
              (if (and new (not (eq new pre)))
                (progn
                  (cdo:fixdim new havestyle)
                  (setq made    (1+ made)
                        dimlist (cons new dimlist)
                        d       (distance (car a) (car b)))
                  (princ (strcat "\n  Pt." (cdr a) " - Pt." (cdr b)
                                 " dimensioned (" (rtos d 4 4) ")."))))
              (setq stage 1))))))

      ;; -- put the drawing back the way it was
      (if (and odim (not (equal odim (getvar "DIMSTYLE"))))
        (cdo:setstyle odim))
      (setvar "CLAYER"  ocl)
      (setvar "OSMODE"  oos)
      (setvar "CMDECHO" oce)
      (command "_.UNDO" "_End")
      (setq grouped nil)

      (princ (strcat "\nCDCALLOUT: " (itoa made) " cross dimension"
                     (if (= made 1) "" "s") " created on layer "
                     cdo:*layer*
                     (if havestyle
                       (strcat " in style " cdo:*style* ".")
                       " (current style).")))))

  (setq *error* olderr)
  (princ))

(defun c:CDCALLOUTVER ()
  (princ (strcat "\nCDCALLOUT " *cdcallout-version*))
  (princ))

(princ (strcat "\nCDCALLOUT " *cdcallout-version*
               " loaded. Command: CDCALLOUT (cross-dimension from"
               " Pt.## to Pt.## by number, style \"" cdo:*style*
               "\", layer \"" cdo:*layer* "\")."))
(princ)
