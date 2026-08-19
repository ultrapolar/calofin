;;; ==========================================================================
;;;  ABCDEF.lsp  -  Plot measured points into AutoCAD from an Excel sheet
;;; --------------------------------------------------------------------------
;;;  Points A B C D sit on the corners of a rectangle:
;;;
;;;        A --------- B         A = top-left      B = top-right
;;;        |           |         C = bottom-left   D = bottom-right
;;;        |           |
;;;        C --------- D         (C sits DIRECTLY BELOW A and D directly
;;;                               below B - the same "Z" reading order as
;;;                               the field sheet, NOT clockwise A-B-C-D)
;;;
;;;  Every labelled point in the sheet is located by its distance from each
;;;  of A, B, C and D.  The command asks for the two rectangle dimensions
;;;  A-B (width) and A-C (height), reads a spreadsheet with the columns
;;;
;;;      POINT NAME | DIST FROM A | DIST FROM B | DIST FROM C | DIST FROM D
;;;
;;;  and multilaterates each point.  Because the supplied distances are
;;;  rounded to the nearest 1/4", no single distance can be trusted exactly;
;;;  a least-squares fit is used so the residual error is shared equally
;;;  among all the distances provided for a point (rather than forcing two
;;;  of them to be exact and dumping all the slop on the rest).
;;;
;;;  Should a sheet label its bottom corners the other way round (C =
;;;  bottom-right, D = bottom-left), the import notices - the distances only
;;;  fit the rectangle one way - swaps C and D to match, and says so.
;;;
;;;  Distances are entered / stored as architectural feet-inches, e.g.
;;;      12'-3 1/2"      3 1/2"      0'-6"      5'-0 3/4"
;;;
;;;  Command:  ABCDEF
;;;
;;;  All geometry is created in inches (1 drawing unit = 1 inch).
;;; ==========================================================================

(vl-load-com)

;; Revision stamp, shown on load and in every run's output.  When plotted
;; points look wrong, FIRST check the drawing/command line shows the rev you
;; think you loaded - two separate field failures turned out to be a stale or
;; hand-edited copy of this file still loaded in AutoCAD.
(setq abcdef:*version* "3")

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
;;;  Dirty-data cleanup helpers (OCR / hand-transcription noise)
;;;
;;;  Field measurements often come back mangled by scanning or re-typing:
;;;    20'_114"      really 20'-1/4"    ( _->-,  114 is 1/4 with / read as 1 )
;;;    1 1'-IO 1/2"  really 11'-10 1/2" ( stray space, I->1, O->0 )
;;;    39'- 8 314"   really 39'-8 3/4"  ( 314 is 3/4 with / read as 1 )
;;;    34'-4 1 /4"   really 34'-4 1/4"  ( fraction split by a stray space )
;;;  These helpers repair that noise deterministically before parsing, and
;;;  flag abcdef:*dirty* so the import can report what it changed.
;;; --------------------------------------------------------------------------

(setq abcdef:*dirty* nil)   ; set T whenever a value needed cleaning
(setq abcdef:*fixes* nil)   ; running list of cleanup / warning messages

;; True if S is one or more chars and every char is a digit 0-9.
(defun abcdef:alldigits (s / ok i a)
  (if (= (strlen s) 0)
    nil
    (progn
      (setq ok T i 1)
      (repeat (strlen s)
        (setq a (ascii (substr s i 1)))
        (if (or (< a 48) (> a 57)) (setq ok nil))
        (setq i (1+ i)))
      ok)))

;; Return the 1-character string for Unicode code point N, but ONLY when this
;; AutoCAD's (chr)/(ascii) round-trip cleanly to that exact point.  On builds
;; where (chr) wraps code points > 255 modulo 256 (some pre-2019 releases),
;; e.g. (chr 8242) -> "2", the round-trip fails and we return nil rather than
;; corrupt real digits.  Everything is caught so it can never raise on load/run.
(defun abcdef:safechr (n / r a)
  (setq r (vl-catch-all-apply 'chr (list n)))
  (if (or (vl-catch-all-error-p r) (/= (type r) 'STR) (/= (strlen r) 1))
    nil
    (progn
      (setq a (vl-catch-all-apply 'ascii (list r)))
      (if (and (not (vl-catch-all-error-p a)) (= a n)) r nil))))

;; True if S contains only characters a feet-inch value may legitimately hold
;; (digits, space, and  "  '  -  .  / ).  Anything else after scrubbing means a
;; genuinely corrupt cell we should flag rather than silently mis-read.
(defun abcdef:parseable-p (s / ok i a)
  (setq ok T i 1)
  (repeat (strlen s)
    (setq a (ascii (substr s i 1)))
    (if (not (or (and (>= a 48) (<= a 57))   ; 0-9
                 (= a 32) (= a 34) (= a 39)   ; space  "  '
                 (= a 45) (= a 46) (= a 47))) ; -  .  /
      (setq ok nil))
    (setq i (1+ i)))
  ok)

;; Character-level scrub of a raw cell: letter / underscore / dash look-alikes
;; and the "smart quote" glyphs Excel/Word insert.  No non-ASCII bytes are
;; embedded in this source (some AutoCAD builds refuse to load such files);
;; single-byte look-alikes use (chr), higher code points go through
;; abcdef:safechr so a build that can't represent them simply skips that pair:
;;   U+2019 ' / U+2032 prime -> '     U+201D " / U+2033 dbl prime -> "
;;   U+2013 en / U+2014 em dash and CP1252 bytes 150/151 -> -
;; These are high-confidence fixes and are NOT flagged as "needs verifying";
;; only the riskier repairs (fraction rebuild, apostrophe-as-1, split feet)
;; set abcdef:*dirty*.
(defun abcdef:scrub (raw / s q)
  (setq s raw)
  (setq s (abcdef:replace s "_" "-"))    ; underscore read for a dash
  (setq s (abcdef:replace s "O" "0"))    ; letter O -> zero
  (setq s (abcdef:replace s "o" "0"))
  (setq s (abcdef:replace s "I" "1"))    ; letter I / l / bar -> one
  (setq s (abcdef:replace s "l" "1"))
  (setq s (abcdef:replace s "|" "1"))
  (setq s (abcdef:replace s (chr 150) "-"))   ; CP1252 en dash byte
  (setq s (abcdef:replace s (chr 151) "-"))   ; CP1252 em dash byte
  (if (setq q (abcdef:safechr 8217)) (setq s (abcdef:replace s q "'")))
  (if (setq q (abcdef:safechr 8242)) (setq s (abcdef:replace s q "'")))
  (if (setq q (abcdef:safechr 8221)) (setq s (abcdef:replace s q "\"")))
  (if (setq q (abcdef:safechr 8243)) (setq s (abcdef:replace s q "\"")))
  (if (setq q (abcdef:safechr 8211)) (setq s (abcdef:replace s q "-")))
  (if (setq q (abcdef:safechr 8212)) (setq s (abcdef:replace s q "-")))
  s)

;; TOK is an all-digit run with no slash.  A fraction like 3/4 whose slash was
;; scanned as a 1 becomes 314; because that substitution keeps the length, a
;; valid inch fraction (den in 2..32, 0<num<den) has exactly one reconstruction.
;; Return "num/den" if one is found (scanning candidate slash positions left to
;; right), else nil.
(defun abcdef:defrac (tok / len k num den ni di best)
  (setq len (strlen tok) k 1 best nil)
  (while (and (<= k len) (null best))
    (if (= (substr tok k 1) "1")
      (progn
        (setq num (substr tok 1 (1- k))
              den (substr tok (1+ k)))
        (if (and (> (strlen num) 0) (> (strlen den) 0)
                 (abcdef:alldigits num) (abcdef:alldigits den))
          (progn
            (setq ni (atoi num) di (atoi den))
            (if (and (member di '(2 4 8 16 32)) (> ni 0) (< ni di))
              (setq best (strcat num "/" den)))))))
    (setq k (1+ k)))
  best)

;; A fraction OCR-split across tokens: "1 /4", "1/ 4" or "1 / 4" tokenises as
;; ("1" "/4"), ("1/" "4") or ("1" "/" "4"), and the broken "/x" piece would
;; otherwise contribute 0 (losing the fraction).  Re-join a token that starts
;; or ends with "/" with its neighbour so the value parses as a real fraction.
(defun abcdef:mergefrac (toks / out tok changed)
  (setq out '() changed nil)
  (while toks
    (setq tok (car toks) toks (cdr toks))
    (cond
      ;; "1/" + "4" -> re-queue "1/4" (also eats the middle of "1 / 4")
      ((and toks (= (substr tok (strlen tok) 1) "/"))
       (setq toks (cons (strcat tok (car toks)) (cdr toks)))
       (setq changed T))
      ;; "1" + "/4" -> "1/4"
      ((and out (> (strlen tok) 1) (= (substr tok 1 1) "/"))
       (setq out (cons (strcat (car out) tok) (cdr out)))
       (setq changed T))
      (T (setq out (cons tok out)))))
  (if changed (setq abcdef:*dirty* T))
  (reverse out))

;;; --------------------------------------------------------------------------
;;;  Feet-inch parser  ->  inches (real).  Returns nil for an empty OR corrupt
;;;  cell.  MAXD, when supplied, is the largest geometrically-possible distance
;;;  (the rectangle's diagonal); it lets the parser recover a foot mark that was
;;;  scanned as a digit and reject impossible values.
;;;
;;;  Accepts, e.g.:  12'-3 1/2"   3 1/2"   0'-6"   5'-0 3/4"   1/2"   18
;;;  and repairs the dirty forms field data comes back in:
;;;    28-7"         missing foot mark    -> 28'-7"   (dash separates ft/in)
;;;    101-10"       foot mark read as 1  -> 10'-10"  (needs MAXD to detect)
;;;    20'-7 114"    "/" read as 1        -> 20'-7 1/4"
;;;    34'-4 1 /4"   fraction split       -> 34'-4 1/4"
;;;    1 1'-IO 1/2"  split feet / O,I     -> 11'-10 1/2"
;;;  Only the non-obvious repairs set abcdef:*dirty* (for the change report).
;;; --------------------------------------------------------------------------

(defun abcdef:ftin->in (raw maxd / s neg feet ftstr rest inch p dp tok
                                    num den slash df val)
  (setq s (abcdef:scrub (abcdef:trim raw)))
  (cond
    ((= s "") nil)                              ; blank cell
    ((not (abcdef:parseable-p s))               ; corrupt char left over
     (setq abcdef:*dirty* T) nil)
    (T
      (setq neg nil)
      (if (= (substr s 1 1) "-") (setq neg T s (abcdef:trim (substr s 2))))
      ;; --- split feet from inches ----------------------------------------
      (setq p (vl-string-search "'" s))
      (cond
        (p                                      ; explicit foot mark
          (setq ftstr (abcdef:trim (substr s 1 p)))
          (if (vl-string-search " " ftstr) (setq abcdef:*dirty* T))
          (setq feet (atof (abcdef:strip ftstr " ")))
          (setq rest (abcdef:trim (substr s (+ p 2)))))
        ((setq dp (vl-string-search "-" s))     ; no ' but a dash: it is the
          (setq ftstr (abcdef:strip (abcdef:trim (substr s 1 dp)) " "))
          (if (vl-string-search " " (abcdef:trim (substr s 1 dp)))
            (setq abcdef:*dirty* T))            ; feet/inch separator
          (setq feet (atof ftstr))
          (setq rest (abcdef:trim (substr s (+ dp 2)))))
        (T (setq feet 0.0 ftstr "" rest s)))    ; inches only
      ;; --- clean the inch remainder --------------------------------------
      (if (= (substr rest 1 1) "-") (setq rest (abcdef:trim (substr rest 2))))
      (setq rest (abcdef:strip rest "\""))   ; drop inch marks
      (setq rest (abcdef:strip rest "'"))    ; and a trailing ' misused as one
      (setq rest (abcdef:replace rest "-" " "))
      (setq rest (abcdef:trim rest))
      ;; --- inches: sum whole-number and fraction tokens ------------------
      (setq inch 0.0)
      (foreach tok (abcdef:mergefrac (abcdef:tokens rest))
        ;; a slash-less all-digit run of 3+ digits is very likely a fraction
        ;; whose "/" was scanned as a "1" (114 -> 1/4); reconstruct it.
        (if (and (not (vl-string-search "/" tok))
                 (>= (strlen tok) 3)
                 (abcdef:alldigits tok)
                 (setq df (abcdef:defrac tok)))
          (setq tok df abcdef:*dirty* T))
        (setq slash (vl-string-search "/" tok))
        (if slash
          (progn
            (setq num (atof (substr tok 1 slash)))
            (setq den (atof (substr tok (+ slash 2))))
            (if (/= den 0.0) (setq inch (+ inch (/ num den)))))
          (setq inch (+ inch (atof tok)))))
      (setq val (+ (* feet 12.0) inch))
      ;; --- foot mark scanned as a "1" ------------------------------------
      ;; e.g. 10'-10" -> "101-10": with no real ' and a value past the
      ;; diagonal, a trailing 1 on the feet was the apostrophe; drop it.
      (if (and maxd (null p) (> val (* maxd 1.05))
               (> (strlen ftstr) 1)
               (= (substr ftstr (strlen ftstr) 1) "1"))
        (progn
          (setq feet (atof (substr ftstr 1 (1- (strlen ftstr))))
                val  (+ (* feet 12.0) inch)
                abcdef:*dirty* T)))
      (if neg (setq val (- val)))
      ;; --- final sanity: non-positive or still impossible -> unreadable --
      (if (or (<= val 0.0) (and maxd (> val (* maxd 1.1))))
        (progn (setq abcdef:*dirty* T) nil)
        val))))

;;; --------------------------------------------------------------------------
;;;  Format inches back to a feet-inch string (for the correction log), to the
;;;  nearest 1/32", reduced.  e.g. 476.75 -> 39'-8 3/4"
;;; --------------------------------------------------------------------------

(defun abcdef:in->ftin (v / neg feet whole frac n den ft s)
  (setq neg (< v 0.0) v (abs v))
  (setq n (fix (+ (* v 32.0) 0.5)))      ; total 1/32" units, rounded
  (setq feet (fix (/ n 384)))            ; 384 = 32*12
  (setq n (- n (* feet 384)))
  (setq whole (fix (/ n 32)))
  (setq n (- n (* whole 32)))            ; leftover 1/32 units, 0..31
  (setq den 32)
  (while (and (> n 0) (= (rem n 2) 0)) (setq n (/ n 2) den (/ den 2)))
  (setq s (strcat (itoa feet) "'-" (itoa whole)))
  (if (> n 0) (setq s (strcat s " " (itoa n) "/" (itoa den))))
  (setq s (strcat s "\""))
  (if neg (strcat "-" s) s))

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

;; Closed 4-vertex polyline through P1 P2 P3 P4, given in PERIMETER order.
;; (With the Z corner naming the perimeter is A-B-D-C; passing A-B-C-D here
;; would draw a bow-tie, so callers hand in positions, not corner names.)
(defun abcdef:frame (p1 p2 p3 p4 layer)
  (entmake (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 layer)
                 '(100 . "AcDbPolyline") '(90 . 4) '(70 . 1)
                 (cons 10 p1) (cons 10 p2) (cons 10 p3) (cons 10 p4))))

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

;; Classify a header cell (already upper-cased) as 'name / 'a / 'b / 'c / 'd.
(defun abcdef:col-of (up)
  (cond ((vl-string-search "FROM A" up) 'a)
        ((vl-string-search "FROM B" up) 'b)
        ((vl-string-search "FROM C" up) 'c)
        ((vl-string-search "FROM D" up) 'd)
        ((or (vl-string-search "NAME" up) (vl-string-search "POINT" up)
             (vl-string-search "LABEL" up)) 'name)
        (T nil)))

;; nth (1-based) element of a list, or "" when the index is nil / out of range.
(defun abcdef:nth-field (lst idx)
  (if (and idx (> idx 0) (<= idx (length lst))) (nth (1- idx) lst) ""))

;; Print the accumulated cleanup / unreadable report (if any).
(defun abcdef:report-fixes (/ m)
  (if abcdef:*fixes*
    (progn
      (princ "\n\n--- dirty values cleaned before import ---")
      (foreach m (reverse abcdef:*fixes*) (princ (strcat "\n" m)))
      (princ "\n  ( * = auto-corrected, ? = unreadable. Verify these! )"))))

;; Parse RAW to inches, logging into abcdef:*fixes* if the value had to be
;; cleaned up (a risky repair) or could not be read at all.  LABEL identifies
;; the cell in the log, e.g. "P3 / FROM C".  MAXD is the rectangle diagonal.
(defun abcdef:parse-log (raw label maxd / clean v)
  (setq clean (abcdef:trim raw))
  (if (= clean "")
    nil                                     ; blank cell: not measured
    (progn
      (setq abcdef:*dirty* nil)
      (setq v (abcdef:ftin->in raw maxd))
      (cond
        ((null v)                           ; nonblank but unreadable
         (setq abcdef:*fixes*
               (cons (strcat "  ? " label ": \"" clean
                             "\"  could not be read - left blank")
                     abcdef:*fixes*)))
        (abcdef:*dirty*                     ; cleaned something up
         (setq abcdef:*fixes*
               (cons (strcat "  * " label ": \"" clean "\"  ->  "
                             (abcdef:in->ftin v))
                     abcdef:*fixes*))))
      v)))

;;; --------------------------------------------------------------------------
;;;  Native CSV reading (no Excel needed).  Preferred for .csv because it also
;;;  avoids Excel silently turning cells like "28-11" or "7-0" into dates.
;;; --------------------------------------------------------------------------

;; Split one CSV line into a list of field strings, honouring "quoted" fields
;; and "" escaped quotes.
(defun abcdef:parse-csv-line (line / fields cur i n c inq)
  (setq fields '() cur "" i 1 n (strlen line))
  ;; state: inq = inside a quoted field
  (setq inq nil)
  (while (<= i n)
    (setq c (substr line i 1))
    (cond
      (inq
        (if (= c "\"")
          (if (= (substr line (1+ i) 1) "\"")   ; "" -> literal quote
            (progn (setq cur (strcat cur "\"")) (setq i (1+ i)))
            (setq inq nil))
          (setq cur (strcat cur c))))
      ((= c "\"") (setq inq T))
      ((= c ",") (setq fields (cons cur fields) cur ""))
      (T (setq cur (strcat cur c))))
    (setq i (1+ i)))
  (setq fields (cons cur fields))
  (reverse fields))

(defun abcdef:read-csv (file maxd / fp line fields i h up kind
                                    name-c a-c b-c c-c d-c rows nm)
  (setq fp (open file "r"))
  (if (null fp)
    (progn (princ "\n** Could not open the file for reading.") nil)
    (progn
      (setq name-c nil a-c nil b-c nil c-c nil d-c nil)
      ;; --- header row (skip any leading blank lines) --------------------
      (setq line (read-line fp))
      (while (and line (= (abcdef:trim (abcdef:strip line (chr 13))) ""))
        (setq line (read-line fp)))
      (if line
        (progn
          (setq fields (abcdef:parse-csv-line (abcdef:strip line (chr 13))) i 1)
          (foreach h fields
            (setq up (strcase (abcdef:trim h)) kind (abcdef:col-of up))
            (cond ((and (eq kind 'name) (null name-c)) (setq name-c i))
                  ((eq kind 'a) (setq a-c i))
                  ((eq kind 'b) (setq b-c i))
                  ((eq kind 'c) (setq c-c i))
                  ((eq kind 'd) (setq d-c i)))
            (setq i (1+ i)))))
      (if (null name-c) (setq name-c 1))     ; fall back to first column
      ;; --- data rows -----------------------------------------------------
      (setq rows '() abcdef:*fixes* '())
      (while (setq line (read-line fp))
        (setq line (abcdef:strip line (chr 13)))
        (if (/= (abcdef:trim line) "")
          (progn
            (setq fields (abcdef:parse-csv-line line))
            (setq nm (abcdef:trim (abcdef:nth-field fields name-c)))
            (if (/= nm "")
              (setq rows
                (cons (list nm
                    (abcdef:parse-log (abcdef:nth-field fields a-c)
                                      (strcat nm " / FROM A") maxd)
                    (abcdef:parse-log (abcdef:nth-field fields b-c)
                                      (strcat nm " / FROM B") maxd)
                    (abcdef:parse-log (abcdef:nth-field fields c-c)
                                      (strcat nm " / FROM C") maxd)
                    (abcdef:parse-log (abcdef:nth-field fields d-c)
                                      (strcat nm " / FROM D") maxd))
                      rows))))))
      (close fp)
      (abcdef:report-fixes)
      (reverse rows))))

;;; --------------------------------------------------------------------------
;;;  Dispatcher: pick the CSV reader for .csv, else Excel COM automation.
;;; --------------------------------------------------------------------------
(defun abcdef:read-file (file maxd / ext n)
  (setq n (strlen file) ext "")
  (if (> n 4) (setq ext (strcase (substr file (- n 3)))))
  (if (= ext ".CSV")
    (abcdef:read-csv file maxd)
    (abcdef:read-excel file maxd)))

(defun abcdef:read-excel (file maxd / xl created wbs wb sheet used rng nrows ncols
                                  hdr r c txt up kind name-c a-c b-c d-c c-c
                                  rows nm da db dc dd err m)
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
            (setq up (strcase (abcdef:xl-cell sheet 1 c)) kind (abcdef:col-of up))
            (cond ((and (eq kind 'name) (null name-c)) (setq name-c c))
                  ((eq kind 'a) (setq a-c c))
                  ((eq kind 'b) (setq b-c c))
                  ((eq kind 'c) (setq c-c c))
                  ((eq kind 'd) (setq d-c c)))
            (setq c (1+ c)))
          (if (null name-c) (setq name-c 1))   ; fall back to first column
          ;; --- read the data rows ----------------------------------------
          (setq rows '() abcdef:*fixes* '() r 2)
          (while (<= r nrows)
            (setq nm (abcdef:xl-cell sheet r name-c))
            (if (/= nm "")
              (setq rows
                (cons (list nm
                    (if a-c (abcdef:parse-log (abcdef:xl-cell sheet r a-c)
                                              (strcat nm " / FROM A") maxd))
                    (if b-c (abcdef:parse-log (abcdef:xl-cell sheet r b-c)
                                              (strcat nm " / FROM B") maxd))
                    (if c-c (abcdef:parse-log (abcdef:xl-cell sheet r c-c)
                                              (strcat nm " / FROM C") maxd))
                    (if d-c (abcdef:parse-log (abcdef:xl-cell sheet r d-c)
                                              (strcat nm " / FROM D") maxd)))
                      rows)))
            (setq r (1+ r)))
          (abcdef:report-fixes)
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

;; With BACK non-nil, typing B (Back; Undo works too) returns the
;; symbol AB-BACK so the caller can re-open its previous question.
(defun abcdef:getdim (prompt back / s v)
  (setq v nil)
  (while (null v)
    (setq s (getstring T (strcat "\n" prompt " (e.g. 20'-6\""
                                 (if back ", B = back" "") "): ")))
    (cond
      ((and back (member (strcase s) '("B" "BACK" "U" "UNDO")))
       (setq v 'AB-BACK))
      (T
       (setq v (abcdef:ftin->in s nil))
       (if (or (null v) (<= v 0.0))
         (progn (princ "  ** enter a positive dimension, e.g. 20'-6\"")
                (setq v nil))))))
  v)

;;; --------------------------------------------------------------------------
;;;  Row geometry helpers
;;; --------------------------------------------------------------------------

;; Build (corners dists) for a row's non-blank distances.  DIN is the row's
;; (dA dB dC dD); PA PB PC PD are the matching corner points as (x y) lists.
(defun abcdef:row-geom (din pa pb pc pd / corners dists)
  (setq corners '() dists '())
  (if (nth 0 din) (setq corners (cons pa corners) dists (cons (nth 0 din) dists)))
  (if (nth 1 din) (setq corners (cons pb corners) dists (cons (nth 1 din) dists)))
  (if (nth 2 din) (setq corners (cons pc corners) dists (cons (nth 2 din) dists)))
  (if (nth 3 din) (setq corners (cons pd corners) dists (cons (nth 3 din) dists)))
  (list (reverse corners) (reverse dists)))

;; RMS fit error of one row solved against the given corner points, or nil
;; when the row has fewer than 2 distances.  CX CY seed the solver.
(defun abcdef:row-rms (din pa pb pc pd cx cy / g)
  (setq g (abcdef:row-geom din pa pb pc pd))
  (if (>= (length (car g)) 2)
    (caddr (abcdef:solve (car g) (cadr g) cx cy))))

;; Verify the named corner variables really form the W x H rectangle they
;; are documented to be: A-B and C-D horizontal sides of length W, A-C and
;; B-D vertical sides of length H, and matching diagonals.  Returns nil when
;; everything is right, else a message naming the first bad measurement.
;; This exists because two field failures traced back to a stale or
;; hand-edited copy of this file whose corner block no longer matched the
;; solver's assumptions - cheap to test on every run, loud when wrong.
(defun abcdef:frame-check (ax ay bx by cx cy dx dy w h / dg chk d bad)
  (setq dg (sqrt (+ (* w w) (* h h))) bad nil)
  (foreach chk (list (list "A-B" ax ay bx by w)
                     (list "C-D" cx cy dx dy w)
                     (list "A-C" ax ay cx cy h)
                     (list "B-D" bx by dx dy h)
                     (list "A-D (diagonal)" ax ay dx dy dg)
                     (list "B-C (diagonal)" bx by cx cy dg))
    (setq d (sqrt (+ (expt (- (nth 3 chk) (nth 1 chk)) 2)
                     (expt (- (nth 4 chk) (nth 2 chk)) 2))))
    (if (and (null bad) (> (abs (- d (nth 5 chk))) 0.001))
      (setq bad (strcat (car chk) " measures " (rtos d 2 2)
                        "\" but should be " (rtos (nth 5 chk) 2 2) "\""))))
  bad)

;; Interior angle in degrees at corner (px py), looking toward (qx qy) and
;; (rx ry).  Measured from the coordinates, NOT assumed - this is what lets
;; the command report honestly that the frame it drew has square corners.
(defun abcdef:corner-ang (px py qx qy rx ry / ux uy vx vy cross dot)
  (setq ux (- qx px) uy (- qy py) vx (- rx px) vy (- ry py))
  (setq cross (- (* ux vy) (* uy vx)) dot (+ (* ux vx) (* uy vy)))
  (if (and (< (abs cross) 1e-12) (< (abs dot) 1e-12))
    0.0
    (* 180.0 (/ (atan (abs cross) dot) pi))))

;;; --------------------------------------------------------------------------
;;;  Main command
;;; --------------------------------------------------------------------------

(defun c:ABCDEF (/ file rows base bx by W H
                    Ax Ay Bx By Cx Cy Dx Dy th mrad
                    good bad r k rr nm din g corners dists
                    sol x y rms tags tg tx ty placed p flag
                    totn tots n3 swapcd tmp angs chk rlist rstr stage done)
  (vl-load-com)
  (princ (strcat "\nABCDEF rev " abcdef:*version*))
  ;; ---- the questions, staged: Back (or Undo) at a later prompt
  ;; ---- re-opens the previous one, back to the file dialog itself
  (setq stage 1 done nil)
  (while (not done)
    (cond
      ;; ---- get the spreadsheet ------------------------------------------
      ((= stage 1)
       (setq file (getfiled "Select points spreadsheet"
                            "" "xlsx;xls;xlsm;csv" 16))
       (if (null file)
         (setq done 'quit)
         (progn
           ;; ---- rectangle dimensions ------------------------------------
           (princ "\n--- Rectangle A(top-left) B(top-right) C(bottom-left) D(bottom-right) ---")
           (setq stage 2))))
      ((= stage 2)
       (setq W (abcdef:getdim "Dimension A-B (width across the top)" T))
       (if (eq W 'AB-BACK) (setq stage 1) (setq stage 3)))
      ((= stage 3)
       (setq H (abcdef:getdim "Dimension A-C (height down the side)" T))
       (if (eq H 'AB-BACK) (setq stage 2) (setq stage 4)))
      ;; ---- where does corner A land? -------------------------------------
      ;; take the pick in WCS so the rectangle is built square to the world
      ;; axes even when the current UCS is rotated (entmake writes WCS).
      (T
       (initget "Back Undo")
       (setq base (getpoint "\nInsertion point for corner A <0,0> [Back]: "))
       (if (= (type base) 'STR) (setq stage 3) (setq done T)))))
  (if (eq done 'quit)
    (progn (princ "\nCancelled.") (princ))
    (progn
      (if base (setq base (trans base 1 0)) (setq base '(0.0 0.0 0.0)))
      (setq bx (car base) by (cadr base))
      ;; Corner coordinates.  A-B runs across the top; C and D sit DIRECTLY
      ;; BELOW A and B (the sheet's "Z" order), so every side is horizontal
      ;; or vertical and all four corners are true right angles:
      ;;    A = (bx, by)       B = (bx+W, by)
      ;;    C = (bx, by-H)     D = (bx+W, by-H)
      (setq Ax bx        Ay by
            Bx (+ bx W)  By by
            Cx bx        Cy (- by H)
            Dx (+ bx W)  Dy (- by H))
      ;; ---- corner self-check ----------------------------------------------
      ;; refuse to plot anything if the corner variables above no longer form
      ;; the W x H rectangle (i.e. this file was edited or a stale copy is
      ;; loaded) - a wrong frame silently poisons every solved point.
      (setq chk (abcdef:frame-check Ax Ay Bx By Cx Cy Dx Dy W H))
      (if chk
        (progn
          (alert (strcat "ABCDEF rev " abcdef:*version*
                         " - corner layout self-check FAILED:\n\n" chk
                         "\n\nThe loaded copy of abcdef.lsp appears stale or"
                         "\nhand-edited.  Re-download abcdef_lisp/abcdef.lsp"
                         "\nand APPLOAD it again.  Nothing was drawn."))
          (princ (strcat "\n** ABORT - corner self-check failed: " chk))
          (princ))
        (progn
      ;; ---- read the sheet ------------------------------------------------
      ;; the rectangle diagonal is the largest distance any point can be from a
      ;; corner; pass it so the parser can spot a foot mark scanned as a digit
      ;; and reject impossible readings.
      (princ "\nReading spreadsheet ... ")
      (setq rows (abcdef:read-file file (sqrt (+ (* W W) (* H H)))))
      (if (null rows)
        (progn (princ "\nNo usable rows found - nothing plotted.") (princ))
        (progn
          (princ (strcat (itoa (length rows)) " row(s) found."))
          ;; ---- do the C / D columns match the corners we assumed? ---------
          ;; Some sheets label the bottom corners the other way round
          ;; (C = bottom-right, D = bottom-left).  The distances only fit the
          ;; rectangle under the labelling they were measured with, so solve
          ;; every 3+-distance row both ways; if swapping C and D fits
          ;; decisively better, adopt the swap and say so.
          (setq totn 0.0 tots 0.0 n3 0)
          (foreach r rows
            (setq din (cdr r) k 0)
            (foreach d din (if d (setq k (1+ k))))
            (if (>= k 3)
              (progn
                (setq rr (abcdef:row-rms din (list Ax Ay) (list Bx By)
                                         (list Cx Cy) (list Dx Dy)
                                         (+ bx (/ W 2.0)) (- by (/ H 2.0))))
                (if rr (setq totn (+ totn rr)))
                (setq rr (abcdef:row-rms din (list Ax Ay) (list Bx By)
                                         (list Dx Dy) (list Cx Cy)
                                         (+ bx (/ W 2.0)) (- by (/ H 2.0))))
                (if rr (setq tots (+ tots rr)))
                (setq n3 (1+ n3)))))
          (setq swapcd nil)
          (if (and (> n3 0)
                   (> totn (* 0.5 n3))        ; poor fit as labelled ...
                   (< tots (* 0.25 totn)))    ; ... and 4x better swapped
            (progn
              (setq swapcd T)
              (setq tmp Cx Cx Dx Dx tmp)
              (setq tmp Cy Cy Dy Dy tmp)
              (princ (strcat
                "\n\n  ** C/D NOTE: the distances fit the opposite bottom corners"
                "\n     far better (avg fit " (rtos (/ tots n3) 2 3)
                "\" swapped vs " (rtos (/ totn n3) 2 3) "\" as labelled)."
                "\n     This sheet labels C = bottom-RIGHT and D = bottom-LEFT;"
                "\n     C and D have been placed that way to match the data."))))
          (if (and (> n3 0) (> (if swapcd tots totn) (* 1.0 n3)))
            (progn
              (princ (strcat
                "\n\n  ** WARNING: the distances fit the rectangle poorly (avg fit "
                (rtos (/ (if swapcd tots totn) n3) 2 3)
                "\").  Check the A-B / A-C dimensions and the sheet values;"
                "\n     the **CHECK flags below mark the worst points."))
              (alert (strcat
                "ABCDEF rev " abcdef:*version*
                ": the distances fit the rectangle POORLY\n(average fit error "
                (rtos (/ (if swapcd tots totn) n3) 2 2)
                "\" - quarter-inch data should fit under 0.10\").\n"
                "\nCheck the A-B / A-C dimensions you entered and the"
                "\nsheet's values.  Points ARE plotted, but every doubtful"
                "\none is flagged CHECK in red in the drawing."))))
          ;; ---- layers & sizing --------------------------------------------
          (abcdef:layer "ABCDEF-FRAME"  1)     ; red
          (abcdef:layer "ABCDEF-POINTS" 2)     ; yellow
          (abcdef:layer "ABCDEF-LABELS" 3)     ; green
          (abcdef:layer "ABCDEF-WARN"   1)     ; red - labels of doubtful fits
          (setq th (/ (max W H) 120.0))        ; text height
          (if (< th 0.5) (setq th 0.5))
          (setq mrad (* th 0.4))               ; marker radius
          ;; ---- draw the rectangle + corner tags ---------------------------
          ;; perimeter order TL -> TR -> BR -> BL, by position (so the frame
          ;; stays a rectangle no matter which naming the sheet used).
          (abcdef:frame (list bx by)
                        (list (+ bx W) by)
                        (list (+ bx W) (- by H))
                        (list bx (- by H))
                        "ABCDEF-FRAME")
          ;; corner name tags, offset outward from whichever corner each
          ;; letter ended up on.
          (setq tags (list (list "A" Ax Ay) (list "B" Bx By)
                           (list "C" Cx Cy) (list "D" Dx Dy)))
          (foreach tg tags
            (setq tx (if (> (cadr tg)  (+ bx (* 0.5 W))) th (* -1 th))
                  ty (if (> (caddr tg) (- by (* 0.5 H))) th (* -1.6 th)))
            (abcdef:text (list (+ (cadr tg) tx) (+ (caddr tg) ty))
                         (* th 1.4) (car tg) "ABCDEF-FRAME"))
          ;; ---- plot each measured point -----------------------------------
          (setq good 0 bad 0 placed '())
          (foreach r rows
            (setq nm (car r) din (cdr r))
            (setq g (abcdef:row-geom din (list Ax Ay) (list Bx By)
                                     (list Cx Cy) (list Dx Dy)))
            (setq corners (car g) dists (cadr g))
            (if (>= (length corners) 2)
              (progn
                (setq sol (abcdef:solve corners dists
                                        (+ bx (/ W 2.0)) (- by (/ H 2.0))))
                (setq x (car sol) y (cadr sol) rms (caddr sol))
                ;; signed leftover error against each supplied distance, in
                ;; sheet order A B C D ("--" = not measured) - shows how the
                ;; quarter-inch rounding slop was shared out over the tapes
                (setq rlist (cdddr sol) rstr "")
                (foreach d din
                  (if d
                    (setq rstr (strcat rstr
                                 (abcdef:pad (abcdef:signres (car rlist)) 7))
                          rlist (cdr rlist))
                    (setq rstr (strcat rstr (abcdef:pad "  --" 7)))))
                (abcdef:point  (list x y) "ABCDEF-POINTS")
                (abcdef:circle (list x y) mrad "ABCDEF-POINTS")
                (setq flag "")
                (if (> rms 0.25) (setq flag "  **CHECK"))
                (if (or (< x (- bx 0.1)) (> x (+ bx W 0.1))
                        (> y (+ by 0.1)) (< y (- by H 0.1)))
                  (setq flag (strcat flag "  (outside frame)")))
                ;; a doubtful fit gets its label in red so the problem is
                ;; visible in the drawing, not only in this report
                (if (> rms 0.25)
                  (abcdef:text (list (+ x (* mrad 1.4)) (+ y (* mrad 1.4)))
                               th (strcat nm " CHECK") "ABCDEF-WARN")
                  (abcdef:text (list (+ x (* mrad 1.4)) (+ y (* mrad 1.4)))
                               th nm "ABCDEF-LABELS"))
                (setq placed (cons (list nm x y rms (length corners) flag rstr)
                                   placed))
                (setq good (1+ good)))
              (progn
                (princ (strcat "\n  ! " nm
                               " : fewer than 2 distances given - skipped."))
                (setq bad (1+ bad)))))
          ;; ---- report ------------------------------------------------------
          (princ (strcat "\n\n===== ABCDEF rev " abcdef:*version*
                         " results (all values in inches) ====="))
          (princ (strcat "\n  POINT            X          Y      #dims"
                         "   fit err (RMS)   err vs A      B      C      D"))
          (foreach p (reverse placed)
            (princ (strcat "\n  " (abcdef:pad (nth 0 p) 14)
                           (abcdef:padnum (nth 1 p) 10)
                           (abcdef:padnum (nth 2 p) 11)
                           "    " (itoa (nth 4 p))
                           "      " (rtos (nth 3 p) 2 4) "\""
                           "     " (nth 6 p) (nth 5 p))))
          (princ (strcat "\n-------------------------------------------------"
                         "\n  " (itoa good) " point(s) plotted"
                         (if (> bad 0) (strcat ", " (itoa bad) " skipped") "")
                         "."))
          (princ (strcat "\n  No single tape is trusted: each point is placed so"
                         "\n  the leftover error is SHARED across all its given"
                         "\n  distances (the signed err columns above).  Rounded"
                         "\n  quarter-inch data typically fits < 0.10\" RMS;"
                         "\n  anything worse than 0.25\" is flagged **CHECK -"
                         "\n  the err columns point at the tape to re-check."))
          ;; ---- confirm the frame really is a rectangle --------------------
          ;; measure the corner angles from the coordinates that were drawn,
          ;; rather than asserting them - so a future corner-math regression
          ;; shows up right here instead of printing a reassuring constant.
          (setq angs (list
            (abcdef:corner-ang bx by (+ bx W) by bx (- by H))
            (abcdef:corner-ang (+ bx W) by bx by (+ bx W) (- by H))
            (abcdef:corner-ang (+ bx W) (- by H) (+ bx W) by bx (- by H))
            (abcdef:corner-ang bx (- by H) bx by (+ bx W) (- by H))))
          (princ (strcat "\n\n  Frame: " (rtos W 2 2) "\" (A-B) x "
                         (rtos H 2 2) "\" (A-C); measured corner angles "
                         (rtos (nth 0 angs) 2 2) " / " (rtos (nth 1 angs) 2 2)
                         " / " (rtos (nth 2 angs) 2 2) " / "
                         (rtos (nth 3 angs) 2 2) " deg."))
          (vl-catch-all-apply
            '(lambda ()
               (vl-cmdf "_.plan" "_World")
               (vl-cmdf "_.zoom" "_Extents")))
          (princ "\n  View reset to plan (top).")
          (princ)))))))
  (princ))

;; right-pad a string to WIDTH
(defun abcdef:pad (s width)
  (while (< (strlen s) width) (setq s (strcat s " ")))
  s)

;; format a signed inches value like "+0.08" (sign always shown, 2 decimals)
(defun abcdef:signres (v)
  (strcat (if (< v 0.0) "-" "+") (rtos (abs v) 2 2)))

;; format a real to 3 decimals, left-padded into WIDTH
(defun abcdef:padnum (v width / s)
  (setq s (rtos v 2 3))
  (while (< (strlen s) width) (setq s (strcat " " s)))
  s)

(princ (strcat "\nABCDEF.lsp rev " abcdef:*version*
               " loaded.  Type ABCDEF to plot points from a spreadsheet."))
(princ)
