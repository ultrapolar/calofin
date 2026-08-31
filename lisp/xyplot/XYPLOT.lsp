;;; ==========================================================================
;;; XYPLOT.lsp  --  Plot an X/Y sheet, twice: as points, and dimensioned
;;; --------------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  XYPLOT      draw both graphs from a spreadsheet of X/Y offsets
;;;            XYPLOTVER   print the loaded version
;;;
;;; ABCDEF's sister command, for the survey that arrives already reduced.
;;; Where ABCDEF is handed four tape distances per point and has to work out
;;; where the point is, XYPLOT is handed the answer - an X and a Y off one
;;; origin - and only has to draw it.  The sheet is
;;;
;;;     POINT NAME | X | Y
;;;
;;; and the command asks for one thing the sheet cannot say: where the
;;; origin goes in the drawing.  Pick that point and both graphs are built
;;; around it.
;;;
;;; TWO GRAPHS, side by side:
;;;
;;;   GRAPH 1 - THE POINTS AS GIVEN.  Every point at its X/Y off the origin,
;;;     labelled with its name from the sheet, drawn as an "ab_pt" block on
;;;     layer POINTS.  That is the same survey point every other calofin
;;;     tool reads, so ABHD, CABHD, ABFIND, BPCALLOUT and LHD pick this
;;;     import up untouched - and the run ends by offering ABHD the set.
;;;
;;;   GRAPH 2 - THE SAME POINTS, DIMENSIONED LINEARLY.  A second copy off to
;;;     the right, with the X offsets dimensioned as one continuous chain
;;;     along the bottom and the Y offsets as another down the left side,
;;;     each dimension's extension lines running back to the point it
;;;     belongs to.  Graph 1 shows you the shape; graph 2 shows you the
;;;     numbers the shape was built from, in the order they run.
;;;
;;; Only graph 1 carries ab_pt blocks.  Graph 2's markers are plain POINTs
;;; on a XYPLOT layer, deliberately: two ab_pt copies of one survey in one
;;; drawing would hand ABHD the same pool twice and it would try to fit a
;;; perimeter around both.
;;;
;;; The dimensions measure the drawn geometry rather than reprinting the
;;; sheet's text, so a value that did not survive the trip shows up as a
;;; dimension that disagrees with its own column in the report.  They land
;;; on layer DIMENSION in the drawing's current dimension style, the same
;;; as AUTODIM's and WCALST's.
;;;
;;; X and Y are read as architectural feet-inches or as plain decimal
;;; inches, negatives included - 12'-3 1/2", -4'-0", 37.25, 3 1/2" all read.
;;; The feet-inch parser is ABCDEF's, including its repairs for scanned and
;;; re-typed field sheets (a split fraction "1 /4", a foot mark read as a
;;; digit, "IO" for "10"), because it is the same handwriting either way.
;;;
;;; All geometry is created in inches (1 drawing unit = 1 inch).
;;; ==========================================================================

(vl-load-com)

;; Version banner, shown on load and at the top of every run's report.
(setq *xyplot-version* "v1.5")

;;; --------------------------------------------------------------------------
;;;  Tunables
;;; --------------------------------------------------------------------------

;; Gap between the two graphs, as a share of graph 1's width.  Wide enough
;; that graph 2's Y dimension chain never runs into graph 1.
(setq xyp:*gutter* 0.35)

;; Two points whose X (or Y) differ by less than this share one rung of the
;; dimension chain - a chain rung of a sixteenth of an inch is unreadable
;; and tells nobody anything.
(setq xyp:*same* 0.0625)

(setq xyp:*dirty* nil)   ; set T whenever a value needed cleaning
(setq xyp:*fixes* nil)   ; running list of cleanup / warning messages

;;; --------------------------------------------------------------------------
;;;  Survey points the rest of the toolkit already understands
;;;  (ABCDEF's block, made the same way - see its header for why.)
;;; --------------------------------------------------------------------------

(setq xyp:*point-layer* "POINTS")
(setq xyp:*point-block* "ab_pt")
(setq xyp:*point-tag*   "number")

;; Trim leading / trailing blanks (spaces, tabs) from a string.
(defun xyp:trim (s / i n)
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
(defun xyp:replace (s old new / out i c)
  (setq out "" i 1)
  (repeat (strlen s)
    (setq c (substr s i 1))
    (setq out (strcat out (if (= c old) new c)))
    (setq i (1+ i)))
  out)

;; Remove every occurrence of the single char CH from S.
(defun xyp:strip (s ch)
  (xyp:replace s ch ""))

;; Split S on spaces, returning a list of non-empty tokens.
(defun xyp:tokens (s / out tok i c)
  (setq out '() tok "" i 1)
  (repeat (strlen s)
    (setq c (substr s i 1))
    (if (= c " ")
      (progn (if (/= tok "") (setq out (cons tok out))) (setq tok ""))
      (setq tok (strcat tok c)))
    (setq i (1+ i)))
  (if (/= tok "") (setq out (cons tok out)))
  (reverse out))

;; True if S is one or more chars and every char is a digit 0-9.
(defun xyp:alldigits (s / ok i a)
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
(defun xyp:safechr (n / r a)
  (setq r (vl-catch-all-apply 'chr (list n)))
  (if (or (vl-catch-all-error-p r) (/= (type r) 'STR) (/= (strlen r) 1))
    nil
    (progn
      (setq a (vl-catch-all-apply 'ascii (list r)))
      (if (and (not (vl-catch-all-error-p a)) (= a n)) r nil))))

;; True if S contains only characters a feet-inch value may legitimately hold
;; (digits, space, and  "  '  -  .  / ).  Anything else after scrubbing means a
;; genuinely corrupt cell we should flag rather than silently mis-read.
(defun xyp:parseable-p (s / ok i a)
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
;; xyp:safechr so a build that can't represent them simply skips that pair:
;;   U+2019 ' / U+2032 prime -> '     U+201D " / U+2033 dbl prime -> "
;;   U+2013 en / U+2014 em dash and CP1252 bytes 150/151 -> -
;; These are high-confidence fixes and are NOT flagged as "needs verifying";
;; only the riskier repairs (fraction rebuild, apostrophe-as-1, split feet)
;; set xyp:*dirty*.
(defun xyp:scrub (raw / s q)
  (setq s raw)
  (setq s (xyp:replace s "_" "-"))    ; underscore read for a dash
  (setq s (xyp:replace s "O" "0"))    ; letter O -> zero
  (setq s (xyp:replace s "o" "0"))
  (setq s (xyp:replace s "I" "1"))    ; letter I / l / bar -> one
  (setq s (xyp:replace s "l" "1"))
  (setq s (xyp:replace s "|" "1"))
  (setq s (xyp:replace s (chr 150) "-"))   ; CP1252 en dash byte
  (setq s (xyp:replace s (chr 151) "-"))   ; CP1252 em dash byte
  (if (setq q (xyp:safechr 8217)) (setq s (xyp:replace s q "'")))
  (if (setq q (xyp:safechr 8242)) (setq s (xyp:replace s q "'")))
  (if (setq q (xyp:safechr 8221)) (setq s (xyp:replace s q "\"")))
  (if (setq q (xyp:safechr 8243)) (setq s (xyp:replace s q "\"")))
  (if (setq q (xyp:safechr 8211)) (setq s (xyp:replace s q "-")))
  (if (setq q (xyp:safechr 8212)) (setq s (xyp:replace s q "-")))
  s)

;; TOK is an all-digit run with no slash.  A fraction like 3/4 whose slash was
;; scanned as a 1 becomes 314; because that substitution keeps the length, a
;; valid inch fraction (den in 2..32, 0<num<den) has exactly one reconstruction.
;; Return "num/den" if one is found (scanning candidate slash positions left to
;; right), else nil.
(defun xyp:defrac (tok / len k num den ni di best)
  (setq len (strlen tok) k 1 best nil)
  (while (and (<= k len) (null best))
    (if (= (substr tok k 1) "1")
      (progn
        (setq num (substr tok 1 (1- k))
              den (substr tok (1+ k)))
        (if (and (> (strlen num) 0) (> (strlen den) 0)
                 (xyp:alldigits num) (xyp:alldigits den))
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
(defun xyp:mergefrac (toks / out tok changed)
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
  (if changed (setq xyp:*dirty* T))
  (reverse out))

(defun xyp:ftin->in (raw maxd / s neg feet ftstr rest inch p dp tok
                                    num den slash df val)
  (setq s (xyp:scrub (xyp:trim raw)))
  (cond
    ((= s "") nil)                              ; blank cell
    ((not (xyp:parseable-p s))               ; corrupt char left over
     (setq xyp:*dirty* T) nil)
    (T
      (setq neg nil)
      (if (= (substr s 1 1) "-") (setq neg T s (xyp:trim (substr s 2))))
      ;; --- split feet from inches ----------------------------------------
      (setq p (vl-string-search "'" s))
      (cond
        (p                                      ; explicit foot mark
          (setq ftstr (xyp:trim (substr s 1 p)))
          (if (vl-string-search " " ftstr) (setq xyp:*dirty* T))
          (setq feet (atof (xyp:strip ftstr " ")))
          (setq rest (xyp:trim (substr s (+ p 2)))))
        ((setq dp (vl-string-search "-" s))     ; no ' but a dash: it is the
          (setq ftstr (xyp:strip (xyp:trim (substr s 1 dp)) " "))
          (if (vl-string-search " " (xyp:trim (substr s 1 dp)))
            (setq xyp:*dirty* T))            ; feet/inch separator
          (setq feet (atof ftstr))
          (setq rest (xyp:trim (substr s (+ dp 2)))))
        (T (setq feet 0.0 ftstr "" rest s)))    ; inches only
      ;; --- clean the inch remainder --------------------------------------
      (if (= (substr rest 1 1) "-") (setq rest (xyp:trim (substr rest 2))))
      (setq rest (xyp:strip rest "\""))   ; drop inch marks
      (setq rest (xyp:strip rest "'"))    ; and a trailing ' misused as one
      (setq rest (xyp:replace rest "-" " "))
      (setq rest (xyp:trim rest))
      ;; --- inches: sum whole-number and fraction tokens ------------------
      (setq inch 0.0)
      (foreach tok (xyp:mergefrac (xyp:tokens rest))
        ;; a slash-less all-digit run of 3+ digits is very likely a fraction
        ;; whose "/" was scanned as a "1" (114 -> 1/4); reconstruct it.
        (if (and (not (vl-string-search "/" tok))
                 (>= (strlen tok) 3)
                 (xyp:alldigits tok)
                 (setq df (xyp:defrac tok)))
          (setq tok df xyp:*dirty* T))
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
                xyp:*dirty* T)))
      (if neg (setq val (- val)))
      ;; --- final sanity: non-positive or still impossible -> unreadable --
      (if (or (<= val 0.0) (and maxd (> val (* maxd 1.1))))
        (progn (setq xyp:*dirty* T) nil)
        val))))

(defun xyp:in->ftin (v / neg feet whole frac n den ft s)
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

;; Coerce a COM cell value to a trimmed string.
(defun xyp:cellstr (v)
  (cond ((null v) "")
        ((= (type v) 'STR) (xyp:trim v))
        ((= (type v) 'REAL) (xyp:trim (rtos v 2 6)))
        ((= (type v) 'INT) (itoa v))
        (T "")))

(defun xyp:xl-cell (sheet r c / res)
  (setq res (vl-catch-all-apply
              '(lambda ()
                 (vlax-variant-value
                   (vlax-get-property
                     (vlax-get-property
                       (vlax-get-property sheet "Cells") "Item" r c)
                     "Text"))) '()))
  (if (vl-catch-all-error-p res) "" (xyp:cellstr res)))

;; nth (1-based) element of a list, or "" when the index is nil / out of range.
(defun xyp:nth-field (lst idx)
  (if (and idx (> idx 0) (<= idx (length lst))) (nth (1- idx) lst) ""))

;; Print the accumulated cleanup / unreadable report (if any).
(defun xyp:report-fixes (/ m)
  (if xyp:*fixes*
    (progn
      (princ "\n\n--- dirty values cleaned before import ---")
      (foreach m (reverse xyp:*fixes*) (princ (strcat "\n" m)))
      (princ "\n  ( * = auto-corrected, ? = unreadable. Verify these! )"))))

;; Parse RAW to inches, logging into xyp:*fixes* if the value had to be
;; cleaned up (a risky repair) or could not be read at all.  LABEL identifies
;; the cell in the log, e.g. "P3 / FROM C".  MAXD is the rectangle diagonal.
(defun xyp:parse-log (raw label maxd / clean v)
  (setq clean (xyp:trim raw))
  (if (= clean "")
    nil                                     ; blank cell: not measured
    (progn
      (setq xyp:*dirty* nil)
      (setq v (xyp:ftin->in raw maxd))
      (cond
        ((null v)                           ; nonblank but unreadable
         (setq xyp:*fixes*
               (cons (strcat "  ? " label ": \"" clean
                             "\"  could not be read - left blank")
                     xyp:*fixes*)))
        (xyp:*dirty*                     ; cleaned something up
         (setq xyp:*fixes*
               (cons (strcat "  * " label ": \"" clean "\"  ->  "
                             (xyp:in->ftin v))
                     xyp:*fixes*))))
      v)))

;; Split one CSV line into a list of field strings, honouring "quoted" fields
;; and "" escaped quotes.
(defun xyp:parse-csv-line (line / fields cur i n c inq)
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

;; right-pad a string to WIDTH
(defun xyp:pad (s width)
  (while (< (strlen s) width) (setq s (strcat s " ")))
  s)

;; format a real to 3 decimals, left-padded into WIDTH
(defun xyp:padnum (v width / s)
  (setq s (rtos v 2 3))
  (while (< (strlen s) width) (setq s (strcat " " s)))
  s)

;;; --------------------------------------------------------------------------
;;;  Reading the sheet
;;;
;;;  Returns a list of rows, each (NAME X Y) with X and Y reals in inches,
;;;  or nil for a cell that was blank or unreadable.  Column order is
;;;  discovered from the header row, so the sheet's columns may sit in any
;;;  order as long as the headers name them.
;;; --------------------------------------------------------------------------

;; Which column a header names.  X and Y are checked as whole words before
;; the looser EASTING / NORTHING spellings, and the name column last, so a
;; header like "X OFFSET" cannot be mistaken for the point name.
(defun xyp:col-of (up)
  (cond ((or (= up "X") (= up "X OFFSET") (= up "OFFSET X")
             (vl-string-search "EASTING" up)
             (and (vl-string-search "X" up)
                  (or (vl-string-search "OFFSET" up)
                      (vl-string-search "COORD" up)
                      (vl-string-search "DIST" up)))) 'x)
        ((or (= up "Y") (= up "Y OFFSET") (= up "OFFSET Y")
             (vl-string-search "NORTHING" up)
             (and (vl-string-search "Y" up)
                  (or (vl-string-search "OFFSET" up)
                      (vl-string-search "COORD" up)
                      (vl-string-search "DIST" up)))) 'y)
        ((or (vl-string-search "NAME" up) (vl-string-search "POINT" up)
             (vl-string-search "LABEL" up) (vl-string-search "NO" up)) 'name)
        (T nil)))

(defun xyp:read-csv (file / fp line fields i h up kind
                            name-c x-c y-c rows nm)
  (setq fp (open file "r"))
  (if (null fp)
    (progn (princ "\n** Could not open the file for reading.") nil)
    (progn
      (setq name-c nil x-c nil y-c nil)
      (setq line (read-line fp))
      (while (and line (= (xyp:trim (xyp:strip line (chr 13))) ""))
        (setq line (read-line fp)))
      (if line
        (progn
          (setq fields (xyp:parse-csv-line (xyp:strip line (chr 13))) i 1)
          (foreach h fields
            (setq up (strcase (xyp:trim h)) kind (xyp:col-of up))
            (cond ((and (eq kind 'name) (null name-c)) (setq name-c i))
                  ((and (eq kind 'x) (null x-c)) (setq x-c i))
                  ((and (eq kind 'y) (null y-c)) (setq y-c i)))
            (setq i (1+ i)))))
      (if (null name-c) (setq name-c 1))     ; fall back to the first column
      (if (null x-c) (setq x-c 2))
      (if (null y-c) (setq y-c 3))
      (setq rows '() xyp:*fixes* '())
      (while (setq line (read-line fp))
        (setq line (xyp:strip line (chr 13)))
        (if (/= (xyp:trim line) "")
          (progn
            (setq fields (xyp:parse-csv-line line))
            (setq nm (xyp:trim (xyp:nth-field fields name-c)))
            (if (/= nm "")
              (setq rows
                (cons (list nm
                        (xyp:parse-log (xyp:nth-field fields x-c)
                                       (strcat nm " / X") nil)
                        (xyp:parse-log (xyp:nth-field fields y-c)
                                       (strcat nm " / Y") nil))
                      rows))))))
      (close fp)
      (xyp:report-fixes)
      (reverse rows))))

(defun xyp:read-excel (file / xl created wbs wb sheet used rng nrows ncols
                              r c up kind name-c x-c y-c rows nm err)
  ;; connect to an existing Excel, else start one.  Structure, error
  ;; handling and object release are ABCDEF's, which is the copy that has
  ;; survived contact with real machines.
  (setq xl (vl-catch-all-apply 'vlax-get-object (list "Excel.Application")))
  (if (vl-catch-all-error-p xl)
    (progn (setq xl (vlax-create-object "Excel.Application") created T)))
  (if (or (null xl) (vl-catch-all-error-p xl))
    (progn (princ "\n** Could not start Excel (is it installed?).") nil)
    (progn
      (vl-catch-all-apply '(lambda () (vlax-put-property xl "Visible" :vlax-false)) '())
      (vl-catch-all-apply '(lambda () (vlax-put-property xl "DisplayAlerts" :vlax-false)) '())
      (setq err (vl-catch-all-apply
                  '(lambda ()
                     (setq wbs (vlax-get-property xl "Workbooks"))
                     (setq wb (vlax-invoke-method wbs "Open" file))
                     (setq sheet (vlax-get-property wb "ActiveSheet"))
                     (setq used (vlax-get-property sheet "UsedRange"))
                     ;; widen columns so "Text" is never truncated to ####
                     (vl-catch-all-apply
                       '(lambda () (vlax-invoke-method
                                     (vlax-get-property used "Columns") "AutoFit")) '())
                     (setq nrows (vlax-get-property
                                   (vlax-get-property used "Rows") "Count"))
                     (setq ncols (vlax-get-property
                                   (vlax-get-property used "Columns") "Count"))) '()))
      (if (vl-catch-all-error-p err)
        (progn
          (princ (strcat "\n** Could not open the spreadsheet: "
                         (vl-catch-all-error-message err)))
          (if created (vl-catch-all-apply '(lambda () (vlax-invoke-method xl "Quit")) '()))
          nil)
        (progn
          ;; --- locate columns from the header row ------------------------
          (setq name-c nil x-c nil y-c nil c 1)
          (while (<= c ncols)
            (setq up (strcase (xyp:xl-cell sheet 1 c)) kind (xyp:col-of up))
            (cond ((and (eq kind 'name) (null name-c)) (setq name-c c))
                  ((and (eq kind 'x) (null x-c)) (setq x-c c))
                  ((and (eq kind 'y) (null y-c)) (setq y-c c)))
            (setq c (1+ c)))
          ;; a sheet with no headers at all is still readable: name, X, Y
          ;; in the first three columns is the shape everyone writes anyway
          (if (null name-c) (setq name-c 1))
          (if (null x-c) (setq x-c 2))
          (if (null y-c) (setq y-c 3))
          ;; --- read the data rows ----------------------------------------
          (setq rows '() xyp:*fixes* '() r 2)
          (while (<= r nrows)
            (setq nm (xyp:xl-cell sheet r name-c))
            (if (/= nm "")
              (setq rows
                (cons (list nm
                        (xyp:parse-log (xyp:xl-cell sheet r x-c)
                                       (strcat nm " / X") nil)
                        (xyp:parse-log (xyp:xl-cell sheet r y-c)
                                       (strcat nm " / Y") nil))
                      rows)))
            (setq r (1+ r)))
          (xyp:report-fixes)
          ;; --- close up --------------------------------------------------
          (vl-catch-all-apply '(lambda () (vlax-invoke-method wb "Close" :vlax-false)) '())
          (if created (vl-catch-all-apply '(lambda () (vlax-invoke-method xl "Quit")) '()))
          (vl-catch-all-apply '(lambda () (vlax-release-object wb)) '())
          (vl-catch-all-apply '(lambda () (vlax-release-object wbs)) '())
          (vl-catch-all-apply '(lambda () (vlax-release-object xl)) '())
          (reverse rows))))))

;; Pick the reader for .csv, else Excel COM automation.
(defun xyp:read-file (file / ext n)
  (setq n (strlen file) ext "")
  (if (> n 4) (setq ext (strcase (substr file (- n 3)))))
  (if (= ext ".CSV")
    (xyp:read-csv file)
    (xyp:read-excel file)))

;;; --------------------------------------------------------------------------
;;;  Drawing helpers
;;; --------------------------------------------------------------------------

(defun xyp:layer (name color / rec ed flags col fixed)
  (if (not (tblsearch "LAYER" name))
    (entmakex (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                    '(100 . "AcDbLayerTableRecord")
                    (cons 2 name) '(70 . 0) (cons 62 color)
                    '(6 . "Continuous")))
    (progn
      (setq rec   (tblobjname "LAYER" name)
            ed    (entget rec)
            flags (cdr (assoc 70 ed))
            col   (cdr (assoc 62 ed))
            fixed nil)
      (if (/= 0 (logand 5 flags))          ; frozen (1) or locked (4)
        (setq ed    (subst (cons 70 (- flags (logand 5 flags)))
                           (assoc 70 ed) ed)
              fixed T))
      (if (< col 0)                        ; layer switched off
        (setq ed    (subst (cons 62 (abs col)) (assoc 62 ed) ed)
              fixed T))
      (if fixed
        (progn
          (entmod ed)
          (princ (strcat "\nLayer " name
                         " was off, frozen or locked - restored so the"
                         " result is visible."))))))
  name)

(defun xyp:point (pt layer)
  (entmake (list '(0 . "POINT") (cons 8 layer)
                 (list 10 (car pt) (cadr pt) 0.0))))

(defun xyp:line (p1 p2 layer)
  (entmake (list '(0 . "LINE") (cons 8 layer)
                 (list 10 (car p1) (cadr p1) 0.0)
                 (list 11 (car p2) (cadr p2) 0.0))))

(defun xyp:text (pt hgt str layer)
  (entmake (list '(0 . "TEXT") (cons 8 layer)
                 (list 10 (car pt) (cadr pt) 0.0)
                 (list 11 (car pt) (cadr pt) 0.0)
                 (cons 40 hgt) (cons 1 str) (cons 72 0) (cons 73 0))))

;; Closed rectangle through the four corners, given in perimeter order.
(defun xyp:box (p1 p2 p3 p4 layer)
  (entmake (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 layer)
                 '(100 . "AcDbPolyline") '(90 . 4) '(70 . 1)
                 (cons 10 p1) (cons 10 p2) (cons 10 p3) (cons 10 p4))))

;; A rotated linear dimension between P1 and P2, its dimension line through
;; LOC.  ROT is 0.0 for a dimension that measures the X difference and
;; pi/2 for one that measures the Y difference, which is what makes each
;; chain read as one straight run of numbers however the points scatter.
;; The extension lines grow from P1 and P2 themselves, so every rung is
;; visibly tied to the two points it spans.
(defun xyp:dim (p1 p2 loc rot layer)
  (entmake (list '(0 . "DIMENSION") '(100 . "AcDbEntity") (cons 8 layer)
                 '(100 . "AcDbDimension")
                 (list 10 (car loc) (cadr loc) 0.0)
                 '(70 . 32) '(1 . "")
                 '(100 . "AcDbAlignedDimension")
                 (list 13 (car p1) (cadr p1) 0.0)
                 (list 14 (car p2) (cadr p2) 0.0)
                 '(100 . "AcDbRotatedDimension")
                 (cons 50 rot))))

;; The ab_pt survey block, built if this drawing has never seen one.
;; (ABCDEF's definition, made the same way, so a drawing can hold imports
;; from both commands without a clash.)
(defun xyp:ensure-block (/ sty)
  (if (not (tblsearch "BLOCK" xyp:*point-block*))
    (progn
      (setq sty (if (tblsearch "STYLE" "STANDARD")
                  "STANDARD"
                  (getvar "TEXTSTYLE")))
      (entmake (list '(0 . "BLOCK") '(100 . "AcDbEntity") '(8 . "0")
                     '(100 . "AcDbBlockBegin")
                     (cons 2 xyp:*point-block*) '(70 . 2)
                     '(10 0.0 0.0 0.0)
                     (cons 3 xyp:*point-block*) '(1 . "")))
      (entmake '((0 . "POINT") (100 . "AcDbEntity") (8 . "0")
                 (100 . "AcDbPoint") (10 0.0 0.0 0.0)))
      (entmake (list '(0 . "ATTDEF") '(100 . "AcDbEntity") '(8 . "0")
                     '(100 . "AcDbText") '(10 1.0 -2.0 0.0) '(40 . 1.0)
                     '(1 . "0") (cons 7 sty)
                     '(100 . "AcDbAttributeDefinition")
                     '(3 . "Type_Point_Number")
                     (cons 2 xyp:*point-tag*) '(70 . 4)))
      (entmake '((0 . "ENDBLK") (100 . "AcDbEntity") (8 . "0")
                 (100 . "AcDbBlockEnd")))
      (princ (strcat "\n  block \"" xyp:*point-block*
                     "\" was not in this drawing - created it."))))
  (tblsearch "BLOCK" xyp:*point-block*))

(defun xyp:insert-pt (pt name th)
  (entmake (list '(0 . "INSERT") '(100 . "AcDbEntity")
                 (cons 8 xyp:*point-layer*)
                 '(100 . "AcDbBlockReference") '(66 . 1)
                 (cons 2 xyp:*point-block*)
                 (list 10 (car pt) (cadr pt) 0.0)
                 (cons 41 th) (cons 42 th) (cons 43 th)))
  (entmake (list '(0 . "ATTRIB") '(100 . "AcDbEntity")
                 (cons 8 xyp:*point-layer*) '(100 . "AcDbText")
                 (list 10 (+ (car pt) th) (- (cadr pt) (* 2.0 th)) 0.0)
                 (cons 40 th) (cons 1 name) '(100 . "AcDbAttribute")
                 (cons 2 xyp:*point-tag*) '(70 . 0)))
  (entmake (list '(0 . "SEQEND") '(100 . "AcDbEntity")
                 (cons 8 xyp:*point-layer*))))

;; Every ab_pt INSERT made since MARK, as a selection set.  (Walking
;; forward from a mark rather than filtering the whole drawing is what
;; keeps a second import from handing ABHD two surveys at once.)
(defun xyp:new-points (mark / ss e ed)
  (setq ss (ssadd) e (if mark (entnext mark) (entnext)))
  (while e
    (setq ed (entget e))
    (if (and (= (cdr (assoc 0 ed)) "INSERT")
             (= (strcase (cdr (assoc 2 ed))) (strcase xyp:*point-block*)))
      (ssadd e ss))
    (setq e (entnext e)))
  ss)

;;; --------------------------------------------------------------------------
;;;  The dimension chains
;;;
;;;  A chain is one continuous run of linear dimensions along an axis,
;;;  passing through every point's offset in order and through the origin
;;;  wherever the origin falls among them.  Read left to right (or bottom to
;;;  top) it is the sheet's column of X (or Y) values turned into the gaps
;;;  between them, which is the form a fitter actually lays out from.
;;;
;;;  Two rules keep it readable.  Offsets closer together than xyp:*same*
;;;  share one stop - a rung a sixteenth of an inch wide is unreadable and
;;;  tells nobody anything.  And the sort is written out longhand rather
;;;  than handed to vl-sort, because vl-sort DROPS elements its comparison
;;;  calls equal: two points on the same X would go in and one would come
;;;  out, silently, which is the worst way for a survey to lose a point.
;;; --------------------------------------------------------------------------

;; STOPS along AXIS ('x or 'y): a list of (VALUE ANCHOR LABELS) sorted by
;; VALUE ascending, including the origin, with points closer than
;; xyp:*same* collapsed onto one stop.  ANCHOR is the drawing point a
;; dimension's extension line grows from; LABELS names the points there.
;;
;; PTS are (NAME X Y) offsets and ORG is where the graph's origin sits.
(defun xyp:chain-stops (pts axis org / raw p v ins out i n cur st)
  ;; --- every offset, plus the origin, as (value anchor label) ------------
  (setq raw (list (list 0.0 org "0")))
  (foreach p pts
    (setq v (if (eq axis 'x) (cadr p) (caddr p)))
    (setq raw (cons (list v
                          (list (+ (car org) (cadr p))
                                (+ (cadr org) (caddr p)))
                          (car p))
                    raw)))
  ;; --- insertion sort by value, ascending, keeping every element ---------
  (setq out '())
  (foreach ins raw
    (setq n (length out) i 0 cur '())
    (while (and (< i n) (<= (car (nth i out)) (car ins)))
      (setq cur (cons (nth i out) cur) i (1+ i)))
    (setq cur (cons ins cur))
    (while (< i n)
      (setq cur (cons (nth i out) cur) i (1+ i)))
    (setq out (reverse cur)))
  ;; --- collapse stops that sit on top of each other ----------------------
  (setq raw '() cur nil)
  (foreach st out
    (if (and cur (<= (abs (- (car st) (car cur))) xyp:*same*))
      ;; same stop: keep the first anchor, add the name to its label
      (setq cur (list (car cur) (cadr cur)
                      (strcat (caddr cur) "," (caddr st))))
      (progn (if cur (setq raw (cons cur raw))) (setq cur st))))
  (if cur (setq raw (cons cur raw)))
  (reverse raw))

;; Draw one chain through STOPS.  AXIS is 'x or 'y; LOC is the coordinate
;; the dimension line sits at (a Y for the X chain, an X for the Y chain).
;; Returns the number of rungs drawn.
(defun xyp:chain (stops axis loc layer / n prev st pa pb dl)
  (setq n 0 prev nil)
  (foreach st stops
    (if prev
      (progn
        (setq pa (cadr prev) pb (cadr st))
        (setq dl (if (eq axis 'x)
                   (list (* 0.5 (+ (car pa) (car pb))) loc)
                   (list loc (* 0.5 (+ (cadr pa) (cadr pb))))))
        (xyp:dim pa pb dl (if (eq axis 'x) 0.0 (/ pi 2.0)) layer)
        (setq n (1+ n))))
    (setq prev st))
  n)

;;; --------------------------------------------------------------------------
;;;  Asking, reporting, handing on
;;; --------------------------------------------------------------------------

;; Keyword question in the house format (STANDARDS.md section 1).  Back and
;; Undo come back as the symbol XY-BACK.
(defun xyp:askkw (msg kws shown dflt back / v)
  (initget (if dflt 0 (if back 0 1))
           (if back (strcat kws " Back Undo") kws))
  (setq v (getkword (strcat "\n" msg " [" shown
                            (if back "/Back" "") "]"
                            (if dflt (strcat " <" dflt ">") "") ": ")))
  (cond ((member v '("Back" "Undo")) 'XY-BACK)
        ((null v) (if dflt dflt (xyp:askkw msg kws shown dflt back)))
        (T v)))

;; Push one report line onto the accumulating list (newest first).
(defun xyp:say (rep line)
  (cons line rep))

;; SHEET with its extension replaced by SUFFIX.
(defun xyp:sibling (sheet suffix / n i cut)
  (setq n (strlen sheet) i n cut nil)
  (while (and (> i 0) (null cut))
    (cond ((= (substr sheet i 1) ".") (setq cut i))
          ((member (substr sheet i 1) '("\\" "/")) (setq i 1)))
    (setq i (1- i)))
  (strcat (if cut (substr sheet 1 (1- cut)) sheet) suffix))

;; Write the report beside the sheet it came from.  Returns the path, or
;; nil - a report that cannot be saved is worth a note, never worth losing
;; the drawing over.
(defun xyp:write-report (sheet lines / path fp ln)
  (setq path (xyp:sibling sheet "_XYPLOT_report.txt"))
  (setq fp (vl-catch-all-apply 'open (list path "w")))
  (if (or (vl-catch-all-error-p fp) (null fp))
    nil
    (progn
      (foreach ln (reverse lines) (write-line ln fp))
      (close fp)
      path)))

;; Pre-select graph 1's points and start ABHD on them.  (ABCDEF's handoff,
;; for the same reason and with the same caveat when ABHD is not loaded.)
(defun xyp:to-abhd (ss / n)
  (setq n (if ss (sslength ss) 0))
  (cond
    ((= n 0)
     (princ "\n  Nothing was plotted, so there is no survey to fit."))
    ((null (boundp 'c:ABHD))
     (princ (strcat "\n  ABHD is not loaded in this drawing, so the points"
                    "\n  were left ready for it instead: they are ab_pt"
                    "\n  blocks on layer " xyp:*point-layer*
                    ".  APPLOAD abhd.lsp (or the"
                    "\n  whole LAZPASS.lsp build), then run ABHD and"
                    "\n  window graph 1's points.")))
    (T
     (princ (strcat "\n  Starting ABHD on the " (itoa n)
                    " point(s) of graph 1 ..."))
     (sssetfirst nil ss)
     (vl-cmdf "_.ABHD"))))

;;; --------------------------------------------------------------------------
;;;  Main command
;;; --------------------------------------------------------------------------

(defun c:XYPLOT (/ *error* undo-open
                    file base bpx bpy rows r nm x y pts skipped
                    minx miny maxx maxy spanx spany th org2 gap
                    xstops ystops xline yline nxd nyd mark ss
                    rep p path stage done g1 g2 pad)
  ;; an Esc mid-plot used to leave a half-drawn plot that took N undos
  ;; to clear and printed a raw AutoLISP message (STANDARDS section 5)
  (defun *error* (msg)
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (setq undo-open nil)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
        (princ (strcat "\nXYPLOT error: " msg)))
    (princ))
  (vl-load-com)
  (princ (strcat "\nXYPLOT " *xyplot-version*))
  ;; ---- the questions: Back at the second re-opens the first -------------
  (setq stage 1 done nil)
  (while (not done)
    (cond
      ((= stage 1)
       (setq file (getfiled "Select X/Y points spreadsheet"
                            "" "xlsx;xls;xlsm;csv" 16))
       (if (null file) (setq done 'quit) (setq stage 2)))
      (T
       ;; take the pick in WCS so the plot is built square to the world axes
       ;; even under a rotated UCS (entmake writes WCS)
       (initget "Back Undo")
       (setq base (getpoint "\nInsertion point for the origin (X=0, Y=0) <0,0> [Back]: "))
       (if (= (type base) 'STR) (setq stage 1) (setq done T)))))
  (if (eq done 'quit)
    (progn (princ "\nCancelled.") (princ))
    (progn
      (command "_.UNDO" "_Begin")
      (setq undo-open T)
      (if base (setq base (trans base 1 0)) (setq base '(0.0 0.0 0.0)))
      (setq bpx (car base) bpy (cadr base))
      (princ "\nReading spreadsheet ... ")
      (setq rows (xyp:read-file file))
      (if (null rows)
        (progn (princ "\nNo usable rows found - nothing plotted.") (princ))
        (progn
          (princ (strcat (itoa (length rows)) " row(s) found."))
          ;; ---- keep the rows that have both an X and a Y ------------------
          (setq pts '() skipped '())
          (foreach r rows
            (setq nm (car r) x (cadr r) y (caddr r))
            (if (and x y)
              (setq pts (cons (list nm x y) pts))
              (setq skipped (cons (list nm (if x "Y" (if y "X" "X and Y")))
                                  skipped))))
          (setq pts (reverse pts) skipped (reverse skipped))
          (if (null pts)
            (progn
              (princ "\nNo row had both an X and a Y - nothing plotted.")
              (princ))
            (progn
              ;; ---- extents, and the sizes everything is drawn from --------
              (setq minx 0.0 maxx 0.0 miny 0.0 maxy 0.0)
              (foreach p pts
                (setq minx (min minx (cadr p)) maxx (max maxx (cadr p))
                      miny (min miny (caddr p)) maxy (max maxy (caddr p))))
              (setq spanx (- maxx minx) spany (- maxy miny))
              (if (< spanx 1.0) (setq spanx 1.0))
              (if (< spany 1.0) (setq spany 1.0))
              (setq th (/ (max spanx spany) 60.0))
              (if (< th 0.5) (setq th 0.5))
              (setq pad (* 2.0 th))
              ;; graph 2 sits a clear gutter to the right of graph 1, far
              ;; enough that its Y chain never overruns graph 1's frame
              (setq gap  (+ (* spanx xyp:*gutter*) (* 12.0 th))
                    org2 (list (+ bpx spanx gap) bpy))
              ;; ---- layers -------------------------------------------------
              (xyp:layer "XYPLOT-FRAME"  1)    ; red   - frames and axes
              (xyp:layer "XYPLOT-POINTS" 2)    ; yellow- graph 2's markers
              (xyp:layer "XYPLOT-LABELS" 3)    ; green - graph 2's names
              (xyp:layer "DIMENSION"     3)    ; green - the chains
              (xyp:layer xyp:*point-layer* 2)  ; yellow- graph 1's survey
              (xyp:ensure-block)
              ;; =============================================================
              ;;  GRAPH 1 - the points as given
              ;; =============================================================
              (setq mark (entlast))
              (foreach p pts
                (xyp:insert-pt (list (+ bpx (cadr p)) (+ bpy (caddr p)))
                               (car p) th))
              (setq ss (xyp:new-points mark))
              ;; axes through the origin, and a frame round the lot
              (xyp:line (list (+ bpx minx (- pad)) bpy)
                        (list (+ bpx maxx pad) bpy) "XYPLOT-FRAME")
              (xyp:line (list bpx (+ bpy miny (- pad)))
                        (list bpx (+ bpy maxy pad)) "XYPLOT-FRAME")
              (setq g1 (list (+ bpx minx (- pad)) (+ bpy miny (- pad))))
              (xyp:box (list (car g1) (cadr g1))
                       (list (+ bpx maxx pad) (cadr g1))
                       (list (+ bpx maxx pad) (+ bpy maxy pad))
                       (list (car g1) (+ bpy maxy pad))
                       "XYPLOT-FRAME")
              (xyp:text (list (car g1) (+ bpy maxy pad (* 0.8 th)))
                        (* 1.6 th) "GRAPH 1 - POINTS AS GIVEN"
                        "XYPLOT-FRAME")
              ;; =============================================================
              ;;  GRAPH 2 - the same points, dimensioned linearly
              ;;  Plain POINTs, not ab_pt: a second ab_pt copy of one survey
              ;;  would hand ABHD the same pool twice.
              ;; =============================================================
              (foreach p pts
                (xyp:point (list (+ (car org2) (cadr p))
                                 (+ (cadr org2) (caddr p)))
                           "XYPLOT-POINTS")
                (xyp:text (list (+ (car org2) (cadr p) (* 0.6 th))
                                (+ (cadr org2) (caddr p) (* 0.6 th)))
                          th (car p) "XYPLOT-LABELS"))
              (xyp:line (list (+ (car org2) minx (- pad)) (cadr org2))
                        (list (+ (car org2) maxx pad) (cadr org2))
                        "XYPLOT-FRAME")
              (xyp:line (list (car org2) (+ (cadr org2) miny (- pad)))
                        (list (car org2) (+ (cadr org2) maxy pad))
                        "XYPLOT-FRAME")
              (setq g2 (list (+ (car org2) minx (- pad))
                             (+ (cadr org2) miny (- pad))))
              (xyp:box (list (car g2) (cadr g2))
                       (list (+ (car org2) maxx pad) (cadr g2))
                       (list (+ (car org2) maxx pad) (+ (cadr org2) maxy pad))
                       (list (car g2) (+ (cadr org2) maxy pad))
                       "XYPLOT-FRAME")
              (xyp:text (list (car g2) (+ (cadr org2) maxy pad (* 0.8 th)))
                        (* 1.6 th) "GRAPH 2 - THE SAME POINTS, DIMENSIONED"
                        "XYPLOT-FRAME")
              ;; the X chain below and the Y chain to the left, each clear
              ;; of the frame so the numbers never sit on the geometry
              (setq xline (- (+ (cadr org2) miny) (* 6.0 th))
                    yline (- (+ (car  org2) minx) (* 6.0 th)))
              (setq xstops (xyp:chain-stops pts 'x org2)
                    ystops (xyp:chain-stops pts 'y org2))
              (setq nxd (xyp:chain xstops 'x xline "DIMENSION")
                    nyd (xyp:chain ystops 'y yline "DIMENSION"))
              (xyp:text (list (car g2) (- xline (* 3.0 th)))
                        th (strcat "X chain: " (itoa nxd) " rungs")
                        "XYPLOT-FRAME")
              (xyp:text (list (- yline (* 2.0 th)) (cadr g2))
                        th (strcat "Y chain: " (itoa nyd) " rungs")
                        "XYPLOT-FRAME")
              ;; ---- report -------------------------------------------------
              (setq rep '())
              (setq rep (xyp:say rep (strcat "===== XYPLOT " *xyplot-version*
                                             " results =====")))
              (setq rep (xyp:say rep (strcat "  sheet  : " file)))
              (setq rep (xyp:say rep (strcat "  origin : "
                                             (rtos bpx 2 3) ", " (rtos bpy 2 3)
                                             " (drawing units = inches)")))
              (setq rep (xyp:say rep ""))
              (setq rep (xyp:say rep
                "  POINT                    X               Y            X (in)      Y (in)"))
              (foreach p pts
                (setq rep (xyp:say rep (strcat
                  "  " (xyp:pad (car p) 20)
                  (xyp:pad (xyp:in->ftin (cadr p)) 16)
                  (xyp:pad (xyp:in->ftin (caddr p)) 14)
                  (xyp:padnum (cadr p) 10)
                  (xyp:padnum (caddr p) 12)))))
              (setq rep (xyp:say rep
                "-------------------------------------------------------------"))
              (setq rep (xyp:say rep (strcat
                "  " (itoa (length pts)) " point(s) plotted in both graphs.")))
              (if skipped
                (progn
                  (setq rep (xyp:say rep (strcat
                    "  " (itoa (length skipped))
                    " row(s) skipped for a missing coordinate:")))
                  (foreach p skipped
                    (setq rep (xyp:say rep (strcat "      " (xyp:pad (car p) 20)
                                                   "no " (cadr p)))))))
              (setq rep (xyp:say rep (strcat
                "  extents: X " (xyp:in->ftin minx) " to " (xyp:in->ftin maxx)
                ",  Y " (xyp:in->ftin miny) " to " (xyp:in->ftin maxy))))
              (setq rep (xyp:say rep (strcat
                "  chains : " (itoa nxd) " X rungs, " (itoa nyd) " Y rungs"
                " (offsets within " (rtos xyp:*same* 2 4)
                "\" share a rung).")))
              (setq rep (xyp:say rep ""))
              (setq rep (xyp:say rep
                "  GRAPH 1 holds the survey: ab_pt blocks on layer POINTS,"))
              (setq rep (xyp:say rep (strcat
                "  numbered from the sheet, which is what ABHD reads.")))
              (setq rep (xyp:say rep
                "  GRAPH 2 is the same points drawn again with the X and Y"))
              (setq rep (xyp:say rep
                "  offsets dimensioned as two continuous chains.  Its markers"))
              (setq rep (xyp:say rep
                "  are plain POINTs on XYPLOT-POINTS, deliberately: a second"))
              (setq rep (xyp:say rep
                "  ab_pt copy would hand ABHD the same pool twice.  The"))
              (setq rep (xyp:say rep
                "  dimensions measure the drawn geometry, so one that"))
              (setq rep (xyp:say rep
                "  disagrees with its column above is a value that did not"))
              (setq rep (xyp:say rep
                "  survive the trip from the sheet."))
              (foreach p (reverse rep) (princ (strcat "\n" p)))
              (setq path (xyp:write-report file rep))
              (princ (if path
                       (strcat "\n\n  Report saved: " path)
                       "\n\n  ** the report file could not be written (read-only folder?)"))
              (vl-catch-all-apply
                '(lambda ()
                   (vl-cmdf "_.plan" "_World")
                   (vl-cmdf "_.zoom" "_Extents"))
                '())
              (princ "\n  View reset to plan (top).")
              ;; close the group before any ABHD handoff - the whole plot
              ;; is one U, and ABHD grouped separately is ABHD's own U
              (command "_.UNDO" "_End")
              (setq undo-open nil)
              ;; ---- on to the pool perimeter ------------------------------
              (if (= "Yes" (xyp:askkw
                             "Fit a pool perimeter through graph 1's points now?"
                             "Yes No" "Yes/No" "Yes" nil))
                (xyp:to-abhd ss)
                (princ "\n  Left as points - run ABHD (or CABHD) when ready."))
              (princ)))))))
  (princ))

;; Print the loaded version.
(defun c:XYPLOTVER ()
  (princ (strcat "\nXYPLOT " *xyplot-version* " (XYPLOT.lsp)"))
  (princ))

(princ (strcat "\nXYPLOT.lsp " *xyplot-version*
               " loaded.  Type XYPLOT to graph an X/Y sheet."))
(princ)
