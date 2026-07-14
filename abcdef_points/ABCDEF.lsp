;;; ==========================================================================
;;;  ABCDEF.lsp  -  Plot measured points into AutoCAD from an Excel sheet
;;; --------------------------------------------------------------------------
;;;  Points A B C D sit on the corners of a rectangle:
;;;
;;;        A --------- B         A = top-left, then clockwise:
;;;        |           |           B = top-right
;;;        |           |           C = bottom-right
;;;        D --------- C           D = bottom-left
;;;
;;;  Every labelled point in the sheet is located by its distance from each
;;;  of A, B, C and D.  The command asks for the two rectangle dimensions
;;;  A-B (width) and A-D (height), reads a spreadsheet with the columns
;;;
;;;      POINT NAME | DIST FROM A | DIST FROM B | DIST FROM C | DIST FROM D
;;;
;;;  and multilaterates each point.  Because the supplied distances are
;;;  rounded to the nearest 1/4", no single distance can be trusted exactly;
;;;  a least-squares fit is used so the residual error is shared equally
;;;  among all the distances provided for a point (rather than forcing two
;;;  of them to be exact and dumping all the slop on the rest).
;;;
;;;  Distances are entered / stored as architectural feet-inches, e.g.
;;;      12'-3 1/2"      3 1/2"      0'-6"      5'-0 3/4"
;;;
;;;  Command:  ABCDEF
;;;
;;;  All geometry is created in inches (1 drawing unit = 1 inch).
;;; ==========================================================================

(vl-load-com)

;;; --------------------------------------------------------------------------
;;;  String helpers
;;; --------------------------------------------------------------------------

;; Trim leading / trailing blanks (spaces, tabs) from a string.
(defun abcdef:trim (s / i n)
  (if (null s) (setq s ""))
  (setq n (strlen s) i 1)
  (while (and (<= i n) (member (substr s i 1) '(" " "\t")))
    (setq i (1+ i)))
  (setq s (substr s i))
  (setq n (strlen s))
  (while (and (> n 0) (member (substr s n 1) '(" " "\t")))
    (setq s (substr s 1 (1- n)) n (1- n)))
  s)

;; Replace every occurrence of the single char OLD with NEW in S.
(defun abcdef:replace (s old new / out i c)
  (setq out "" i 1)
  (repeat (strlen s)
    (setq c (substr s i 1))
    (setq out (strcat out (if (= c old) new c)))
    (setq i (1+ i)))
  out)

;; Remove every occurrence of the single char CH from S.
(defun abcdef:strip (s ch)
  (abcdef:replace s ch ""))

;; Split S on spaces, returning a list of non-empty tokens.
(defun abcdef:tokens (s / out tok i c)
  (setq out '() tok "" i 1)
  (repeat (strlen s)
    (setq c (substr s i 1))
    (if (= c " ")
      (progn (if (/= tok "") (setq out (cons tok out))) (setq tok ""))
      (setq tok (strcat tok c)))
    (setq i (1+ i)))
  (if (/= tok "") (setq out (cons tok out)))
  (reverse out))

;;; --------------------------------------------------------------------------
;;;  Feet-inch parser  ->  inches (real).  Returns nil on an empty cell.
;;;
;;;  Accepts, e.g.:  12'-3 1/2"   3 1/2"   0'-6"   5'-0 3/4"   1/2"   18   6.25
;;;  Feet/inch marks (' ") are optional; the whole-inch and fraction may be
;;;  separated by a space or a dash.
;;; --------------------------------------------------------------------------

(defun abcdef:ftin->in (raw / s neg feet rest inch p tok num den slash)
  (setq s (abcdef:trim raw))
  ;; normalise the "smart quote" glyphs Excel/Word sometimes substitute for
  ;; the plain foot (') and inch (") marks, without embedding any non-ASCII
  ;; bytes in this source file (which some AutoCAD builds refuse to load):
  ;;   right single quote U+2019 and prime U+2032  ->  '
  ;;   right double quote U+201D and double prime U+2033  ->  "
  (setq s (abcdef:replace s (chr 8217) "'"))
  (setq s (abcdef:replace s (chr 8242) "'"))
  (setq s (abcdef:replace s (chr 8221) "\""))
  (setq s (abcdef:replace s (chr 8243) "\""))
  (if (= s "")
    nil
    (progn
      ;; leading minus?
      (setq neg nil)
      (if (= (substr s 1 1) "-") (setq neg T s (abcdef:trim (substr s 2))))
      ;; --- feet, up to the foot mark -------------------------------------
      (setq p (vl-string-search "'" s))
      (if p
        (progn
          (setq feet (atof (abcdef:trim (substr s 1 p))))
          (setq rest (abcdef:trim (substr s (+ p 2)))))
        (setq feet 0.0 rest s))
      ;; between feet and inches there is often a '-' separator: drop a
      ;; single leading dash, then treat remaining dashes as spaces so a
      ;; whole-inch/fraction pair like 3-1/2 is tokenised correctly.
      (if (= (substr rest 1 1) "-") (setq rest (abcdef:trim (substr rest 2))))
      (setq rest (abcdef:strip rest "\""))   ; drop inch marks
      (setq rest (abcdef:replace rest "-" " "))
      (setq rest (abcdef:trim rest))
      ;; --- inches: sum whole-number and fraction tokens ------------------
      (setq inch 0.0)
      (foreach tok (abcdef:tokens rest)
        (setq slash (vl-string-search "/" tok))
        (if slash
          (progn
            (setq num (atof (substr tok 1 slash)))
            (setq den (atof (substr tok (+ slash 2))))
            (if (/= den 0.0) (setq inch (+ inch (/ num den)))))
          (setq inch (+ inch (atof tok)))))
      (setq inch (+ (* feet 12.0) inch))
      (if neg (- inch) inch))))

;;; --------------------------------------------------------------------------
;;;  Multilateration
;;;
;;;  CORNERS : list of (x y) corner coordinates that have a distance
;;;  DISTS   : matching list of measured distances
;;;  Returns : (x y rms res1 res2 ...)  in the same local frame as CORNERS.
;;;
;;;  A linear (circle-difference) solution seeds a Gauss-Newton refinement
;;;  of  min  S( |P-Ci| - di )^2 , which is exactly "spread the rounding
;;;  error evenly over the distances".  Needs >= 2 corners; 3+ give a unique
;;;  fix.  With only 2, the frame centre is used as the seed so the interior
;;;  intersection is chosen.
;;; --------------------------------------------------------------------------

(defun abcdef:solve (corners dists cx cy / n x y i c d dx dy r jx jy f
                             saa sab sbb sac sbc a b cc det xr yr dr
                             jaa jab jbb ga gb ddx ddy res rms iter)
  (setq n (length corners))
  ;; ---- seed --------------------------------------------------------------
  (if (>= n 3)
    (progn                                   ; linear least squares seed
      (setq xr (car (car corners)) yr (cadr (car corners)) dr (car dists))
      (setq saa 0.0 sab 0.0 sbb 0.0 sac 0.0 sbc 0.0 i 1)
      (while (< i n)
        (setq c (nth i corners) d (nth i dists))
        (setq a (* 2.0 (- (car c) xr))
              b (* 2.0 (- (cadr c) yr))
              cc (- (- (+ (* (car c) (car c)) (* (cadr c) (cadr c)))
                       (+ (* xr xr) (* yr yr)))
                    (- (* d d) (* dr dr))))
        (setq saa (+ saa (* a a)) sab (+ sab (* a b)) sbb (+ sbb (* b b))
              sac (+ sac (* a cc)) sbc (+ sbc (* b cc)))
        (setq i (1+ i)))
      (setq det (- (* saa sbb) (* sab sab)))
      (if (> (abs det) 1e-9)
        (setq x (/ (- (* sac sbb) (* sbc sab)) det)
              y (/ (- (* saa sbc) (* sab sac)) det))
        (setq x cx y cy)))                    ; degenerate -> centre
    (setq x cx y cy))                         ; only 2 circles -> centre seed
  ;; ---- Gauss-Newton refinement ------------------------------------------
  (setq iter 0)
  (while (< iter 60)
    (setq jaa 0.0 jab 0.0 jbb 0.0 ga 0.0 gb 0.0 i 0)
    (while (< i n)
      (setq c (nth i corners) d (nth i dists))
      (setq dx (- x (car c)) dy (- y (cadr c)) r (sqrt (+ (* dx dx) (* dy dy))))
      (if (< r 1e-9) (setq r 1e-9))
      (setq jx (/ dx r) jy (/ dy r) f (- r d))
      (setq jaa (+ jaa (* jx jx)) jab (+ jab (* jx jy)) jbb (+ jbb (* jy jy))
            ga (+ ga (* jx f)) gb (+ gb (* jy f)))
      (setq i (1+ i)))
    (setq det (- (* jaa jbb) (* jab jab)))
    (if (< (abs det) 1e-12)
      (setq iter 60)                          ; singular -> stop
      (progn
        (setq ddx (/ (- (- (* ga jbb)) (- (* gb jab)))
                     det)
              ddy (/ (- (- (* jaa gb)) (- (* jab ga)))
                     det))
        ;; ddx = -(ga*jbb - gb*jab)/det ; ddy = -(jaa*gb - jab*ga)/det
        (setq x (+ x ddx) y (+ y ddy))
        (if (and (< (abs ddx) 1e-7) (< (abs ddy) 1e-7)) (setq iter 60))))
    (setq iter (1+ iter)))
  ;; ---- residuals ---------------------------------------------------------
  (setq res '() rms 0.0 i 0)
  (while (< i n)
    (setq c (nth i corners) d (nth i dists))
    (setq f (- (sqrt (+ (expt (- x (car c)) 2) (expt (- y (cadr c)) 2))) d))
    (setq res (cons f res) rms (+ rms (* f f)) i (1+ i)))
  (setq rms (sqrt (/ rms n)))
  (cons x (cons y (cons rms (reverse res)))))

;;; --------------------------------------------------------------------------
;;;  Drawing helpers
;;; --------------------------------------------------------------------------

;; Make sure a layer exists (create it with COLOR if not).
(defun abcdef:layer (name color)
  (if (not (tblsearch "LAYER" name))
    (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord") (cons 2 name)
                   '(70 . 0) (cons 62 color) '(6 . "Continuous")))))

(defun abcdef:point (pt layer)
  (entmake (list '(0 . "POINT") (cons 8 layer)
                 (cons 10 (list (car pt) (cadr pt) 0.0)))))

(defun abcdef:circle (pt rad layer)
  (entmake (list '(0 . "CIRCLE") (cons 8 layer)
                 (cons 10 (list (car pt) (cadr pt) 0.0)) (cons 40 rad))))

(defun abcdef:text (pt hgt str layer)
  (entmake (list '(0 . "TEXT") (cons 8 layer)
                 (cons 10 (list (car pt) (cadr pt) 0.0))
                 (cons 11 (list (car pt) (cadr pt) 0.0))
                 (cons 40 hgt) (cons 1 str) (cons 72 0) (cons 73 0))))

;; Closed 4-vertex polyline A B C D.
(defun abcdef:frame (a b c d layer)
  (entmake (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 layer)
                 '(100 . "AcDbPolyline") '(90 . 4) '(70 . 1)
                 (cons 10 a) (cons 10 b) (cons 10 c) (cons 10 d))))

;;; --------------------------------------------------------------------------
;;;  Excel reading (via COM automation)
;;;
;;;  Returns a list of rows, each  (name dA dB dC dD)  where any dX is a real
;;;  (inches) or nil when that cell was blank.  Column order is discovered
;;;  from the header row, so the sheet's columns may be in any order as long
;;;  as the headers contain NAME / FROM A / FROM B / FROM C / FROM D.
;;; --------------------------------------------------------------------------

;; Coerce a COM cell value to a trimmed string.
(defun abcdef:cellstr (v)
  (cond ((null v) "")
        ((= (type v) 'STR) (abcdef:trim v))
        ((= (type v) 'REAL) (abcdef:trim (rtos v 2 6)))
        ((= (type v) 'INT) (itoa v))
        (T "")))

(defun abcdef:xl-cell (sheet r c / res)
  (setq res (vl-catch-all-apply
              '(lambda ()
                 (vlax-variant-value
                   (vlax-get-property
                     (vlax-get-property
                       (vlax-get-property sheet "Cells") "Item" r c)
                     "Text")))))
  (if (vl-catch-all-error-p res) "" (abcdef:cellstr res)))

(defun abcdef:read-excel (file / xl created wbs wb sheet used rng nrows ncols
                                  hdr r c txt up name-c a-c b-c d-c c-c
                                  rows nm da db dc dd err)
  ;; connect to an existing Excel, else start one
  (setq xl (vl-catch-all-apply 'vlax-get-object (list "Excel.Application")))
  (if (vl-catch-all-error-p xl)
    (progn (setq xl (vlax-create-object "Excel.Application") created T)))
  (if (or (null xl) (vl-catch-all-error-p xl))
    (progn (princ "\n** Could not start Excel (is it installed?).") nil)
    (progn
      (vl-catch-all-apply '(lambda () (vlax-put-property xl "Visible" :vlax-false)))
      (vl-catch-all-apply '(lambda () (vlax-put-property xl "DisplayAlerts" :vlax-false)))
      (setq err (vl-catch-all-apply
                  '(lambda ()
                     (setq wbs (vlax-get-property xl "Workbooks"))
                     (setq wb (vlax-invoke-method wbs "Open" file))
                     (setq sheet (vlax-get-property wb "ActiveSheet"))
                     (setq used (vlax-get-property sheet "UsedRange"))
                     ;; widen columns so "Text" is never truncated to ####
                     (vl-catch-all-apply
                       '(lambda () (vlax-invoke-method
                                     (vlax-get-property used "Columns") "AutoFit")))
                     (setq nrows (vlax-get-property
                                   (vlax-get-property used "Rows") "Count"))
                     (setq ncols (vlax-get-property
                                   (vlax-get-property used "Columns") "Count")))))
      (if (vl-catch-all-error-p err)
        (progn
          (princ (strcat "\n** Could not open the spreadsheet: "
                         (vl-catch-all-error-message err)))
          (if created (vl-catch-all-apply '(lambda () (vlax-invoke-method xl "Quit"))))
          nil)
        (progn
          ;; --- locate columns from the header row ------------------------
          (setq name-c nil a-c nil b-c nil c-c nil d-c nil c 1)
          (while (<= c ncols)
            (setq up (strcase (abcdef:xl-cell sheet 1 c)))
            (cond
              ((and (null name-c)
                    (or (vl-string-search "NAME" up)
                        (vl-string-search "POINT" up)
                        (vl-string-search "LABEL" up)))     (setq name-c c))
              ((vl-string-search "FROM A" up)               (setq a-c c))
              ((vl-string-search "FROM B" up)               (setq b-c c))
              ((vl-string-search "FROM C" up)               (setq c-c c))
              ((vl-string-search "FROM D" up)               (setq d-c c)))
            (setq c (1+ c)))
          (if (null name-c) (setq name-c 1))   ; fall back to first column
          ;; --- read the data rows ----------------------------------------
          (setq rows '() r 2)
          (while (<= r nrows)
            (setq nm (abcdef:xl-cell sheet r name-c))
            (if (/= nm "")
              (setq rows
                (cons (list nm
                            (if a-c (abcdef:ftin->in (abcdef:xl-cell sheet r a-c)))
                            (if b-c (abcdef:ftin->in (abcdef:xl-cell sheet r b-c)))
                            (if c-c (abcdef:ftin->in (abcdef:xl-cell sheet r c-c)))
                            (if d-c (abcdef:ftin->in (abcdef:xl-cell sheet r d-c))))
                      rows)))
            (setq r (1+ r)))
          ;; --- close up --------------------------------------------------
          (vl-catch-all-apply '(lambda () (vlax-invoke-method wb "Close" :vlax-false)))
          (if created (vl-catch-all-apply '(lambda () (vlax-invoke-method xl "Quit"))))
          (vl-catch-all-apply '(lambda () (vlax-release-object wb)))
          (vl-catch-all-apply '(lambda () (vlax-release-object wbs)))
          (vl-catch-all-apply '(lambda () (vlax-release-object xl)))
          (reverse rows))))))

;;; --------------------------------------------------------------------------
;;;  Prompt helper: read a feet-inch dimension from the keyboard.
;;; --------------------------------------------------------------------------

(defun abcdef:getdim (prompt / s v)
  (setq v nil)
  (while (null v)
    (setq s (getstring T (strcat "\n" prompt " (e.g. 20'-6\"): ")))
    (setq v (abcdef:ftin->in s))
    (if (or (null v) (<= v 0.0))
      (progn (princ "  ** enter a positive dimension, e.g. 20'-6\"") (setq v nil))))
  v)

;;; --------------------------------------------------------------------------
;;;  Main command
;;; --------------------------------------------------------------------------

(defun c:ABCDEF (/ file rows base bx by W H
                    Ax Ay Bx By Cx Cy Dx Dy th mrad
                    good bad r nm din corners dists lbl
                    sol x y rms i tags placed)
  (vl-load-com)
  ;; ---- get the spreadsheet ----------------------------------------------
  (setq file (getfiled "Select points spreadsheet"
                       "" "xlsx;xls;xlsm;csv" 16))
  (if (null file)
    (progn (princ "\nCancelled.") (princ))
    (progn
      ;; ---- rectangle dimensions ------------------------------------------
      (princ "\n--- Rectangle A(top-left) B(top-right) C(bottom-right) D(bottom-left) ---")
      (setq W (abcdef:getdim "Dimension A-B (width across the top)"))
      (setq H (abcdef:getdim "Dimension A-D (height down the side)"))
      ;; ---- where does corner A land? -------------------------------------
      (setq base (getpoint "\nInsertion point for corner A <0,0>: "))
      (if (null base) (setq base '(0.0 0.0 0.0)))
      (setq bx (car base) by (cadr base))
      ;; corner coordinates: A top-left, clockwise, Y up (A-D goes down)
      (setq Ax bx        Ay by
            Bx (+ bx W)  By by
            Cx (+ bx W)  Cy (- by H)
            Dx bx        Dy (- by H))
      ;; ---- read the sheet ------------------------------------------------
      (princ "\nReading spreadsheet ... ")
      (setq rows (abcdef:read-excel file))
      (if (null rows)
        (progn (princ "\nNo usable rows found - nothing plotted.") (princ))
        (progn
          (princ (strcat (itoa (length rows)) " row(s) found."))
          ;; ---- layers & sizing --------------------------------------------
          (abcdef:layer "ABCDEF-FRAME"  1)     ; red
          (abcdef:layer "ABCDEF-POINTS" 2)     ; yellow
          (abcdef:layer "ABCDEF-LABELS" 3)     ; green
          (setq th (/ (max W H) 120.0))        ; text height
          (if (< th 0.5) (setq th 0.5))
          (setq mrad (* th 0.4))               ; marker radius
          ;; ---- draw the rectangle + corner tags ---------------------------
          (abcdef:frame (list Ax Ay) (list Bx By) (list Cx Cy) (list Dx Dy)
                        "ABCDEF-FRAME")
          (setq tags (list (list "A" Ax Ay (* -1 th) th)
                           (list "B" Bx By th th)
                           (list "C" Cx Cy th (* -1.6 th))
                           (list "D" Dx Dy (* -1 th) (* -1.6 th))))
          (foreach tg tags
            (abcdef:text (list (+ (nth 1 tg) (nth 3 tg))
                               (+ (nth 2 tg) (nth 4 tg)))
                         (* th 1.4) (car tg) "ABCDEF-FRAME"))
          ;; ---- plot each measured point -----------------------------------
          (setq good 0 bad 0 placed '())
          (foreach r rows
            (setq nm (car r) din (cdr r))
            ;; build parallel corner / distance lists for the provided dims
            (setq corners '() dists '())
            (if (nth 0 din) (setq corners (cons (list Ax Ay) corners)
                                  dists   (cons (nth 0 din) dists)))
            (if (nth 1 din) (setq corners (cons (list Bx By) corners)
                                  dists   (cons (nth 1 din) dists)))
            (if (nth 2 din) (setq corners (cons (list Cx Cy) corners)
                                  dists   (cons (nth 2 din) dists)))
            (if (nth 3 din) (setq corners (cons (list Dx Dy) corners)
                                  dists   (cons (nth 3 din) dists)))
            (if (>= (length corners) 2)
              (progn
                (setq sol (abcdef:solve (reverse corners) (reverse dists)
                                        (+ bx (/ W 2.0)) (- by (/ H 2.0))))
                (setq x (car sol) y (cadr sol) rms (caddr sol))
                (abcdef:point  (list x y) "ABCDEF-POINTS")
                (abcdef:circle (list x y) mrad "ABCDEF-POINTS")
                (abcdef:text   (list (+ x (* mrad 1.4)) (+ y (* mrad 1.4)))
                               th nm "ABCDEF-LABELS")
                (setq placed (cons (list nm x y rms (length corners)) placed))
                (setq good (1+ good)))
              (progn
                (princ (strcat "\n  ! " nm
                               " : fewer than 2 distances given - skipped."))
                (setq bad (1+ bad)))))
          ;; ---- report ------------------------------------------------------
          (princ "\n\n===== ABCDEF results (all values in inches) =====")
          (princ "\n  POINT            X          Y      #dims   fit err (RMS)")
          (foreach p (reverse placed)
            (princ (strcat "\n  " (abcdef:pad (nth 0 p) 14)
                           (abcdef:padnum (nth 1 p) 10)
                           (abcdef:padnum (nth 2 p) 11)
                           "    " (itoa (nth 4 p))
                           "      " (rtos (nth 3 p) 2 4) "\"")))
          (princ (strcat "\n-------------------------------------------------"
                         "\n  " (itoa good) " point(s) plotted"
                         (if (> bad 0) (strcat ", " (itoa bad) " skipped") "")
                         "."))
          (princ (strcat "\n  Fit err (RMS) is the leftover rounding error shared"
                         "\n  across the given distances - typically < 0.10\" for"
                         "\n  quarter-inch data.  A large value means a bad reading."))
          (princ)))))
  (princ))

;; right-pad a string to WIDTH
(defun abcdef:pad (s width)
  (while (< (strlen s) width) (setq s (strcat s " ")))
  s)

;; format a real to 3 decimals, left-padded into WIDTH
(defun abcdef:padnum (v width / s)
  (setq s (rtos v 2 3))
  (while (< (strlen s) width) (setq s (strcat " " s)))
  s)

(princ "\nABCDEF.lsp loaded.  Type ABCDEF to plot points from a spreadsheet.")
(princ)
