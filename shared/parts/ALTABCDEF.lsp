;;; ==========================================================================
;;;  ALTABCDEF.lsp  -  Plot measured points into AutoCAD from an Excel sheet
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
;;;  ABCDEF is this command's sister, for a sheet whose bottom corners are
;;;  labelled the other way round (C bottom-LEFT, D bottom-RIGHT - the "Z"
;;;  reading order).  The two conventions are not interchangeable, which is
;;;  why they are two commands; ABCDEF is the one that has grown the
;;;  confidence report, the tape-dropping rules and the C/D detector.
;;;
;;;  Commands:  ALTABCDEF     read the sheet and plot every point
;;;             ALTABCDEFVER  print the loaded version
;;;
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;
;;;  Every threshold, layer name, colour, size and tolerance the command
;;;  uses is a named Tunable at the top of this file, each with a note on
;;;  what it does and which way to move it.  Nothing below that block is
;;;  meant to be edited to change how the tool behaves.
;;;
;;;  All geometry is created in inches (1 drawing unit = 1 inch).
;;; ==========================================================================

(setq *altabcdef-version* "v1.8")   ; announced on load; release_lisp.py
                                       ; stamps the dated twin in releases/

(vl-load-com)

;;; -------------------- tunables ----------------------------------------
;;
;; Everything a drafter might reasonably want different is set HERE and
;; nowhere else: the code below reads these names and carries no bare
;; numbers of its own.  Each knob says what CHANGING it does, what unit
;; it is in, and which way to move it.  Change a value, save, APPLOAD
;; again - or (setq altabcdef:*name* value) at the command line for one
;; session.  Every one of them is a row in README.md's Tunables table,
;; and tests/test_tunables.py holds the two together.
;;
;; Distances are in inches throughout (1 drawing unit = 1 inch).

;; ---- what it draws ---------------------------------------------------------

;; The three output layers and the colours they are created with (AutoCAD
;; colour numbers: 1 red, 2 yellow, 3 green).  A layer that already exists
;; keeps its own colour and is only switched on, thawed and unlocked.
;;
;; These are ALTABCDEF's own layers on purpose.  ABCDEF plots onto the
;; shared POINTS layer as "ab_pt" blocks, which ABHD and the other fitters
;; read; this command draws plain markers instead, so pointing it at POINTS
;; would put entities there that those tools would try to fit a pool
;; through.  Change these only if you know what reads them.
(setq altabcdef:*frame-layer*  "ALTABCDEF-FRAME")
(setq altabcdef:*frame-color*  1)
(setq altabcdef:*point-layer*  "ALTABCDEF-POINTS")
(setq altabcdef:*point-color*  2)
(setq altabcdef:*label-layer*  "ALTABCDEF-LABELS")
(setq altabcdef:*label-color*  3)

;; Text height is the longer rectangle side divided by *text-div*, but
;; never under *text-min* inches.  Everything else is measured in those
;; text heights:
;;   *marker-scale*  radius of the circle drawn around each point
;;   *label-off*     how far up and right of the point its name sits, in
;;                   marker radii
;;   *tag-scale*     the corner letters A B C D are this many text heights
;;   *tag-gap*       how far a corner letter sits out from its corner,
;;                   sideways and upward
;;   *tag-drop*      how far BELOW a bottom corner its letter's baseline
;;                   sits (more than *tag-gap*: the letter's own height
;;                   has to clear the corner)
(setq altabcdef:*text-div*     120.0)
(setq altabcdef:*text-min*     0.5)
(setq altabcdef:*marker-scale* 0.4)
(setq altabcdef:*label-off*    1.4)
(setq altabcdef:*tag-scale*    1.4)
(setq altabcdef:*tag-gap*      1.0)
(setq altabcdef:*tag-drop*     1.6)

;; ---- the sheet -------------------------------------------------------------

;; What the file dialog offers, as a getfiled extension list.  CSV is read
;; natively; the Excel formats go through Excel COM automation and so need
;; full AutoCAD with Excel installed.
(setq altabcdef:*file-types* "xlsx;xls;xlsm;csv")

;; Header words that identify the columns, compared upper-case as
;; substrings: a header containing the Nth entry of *hdr-dist* is the
;; distance from the Nth corner (A B C D), and the first header containing
;; any entry of *hdr-name* is the point name.  With no name header the
;; first column is taken.
(setq altabcdef:*hdr-dist* '("FROM A" "FROM B" "FROM C" "FROM D"))
(setq altabcdef:*hdr-name* '("NAME" "POINT" "LABEL"))

;; How many distances a row needs before it is plotted at all.  Two fix a
;; point up to a mirror, three fix it outright.  Below this the row is
;; skipped and named on the command line.
(setq altabcdef:*min-tapes* 2)

;; ---- reading dirty values --------------------------------------------------

;; A reading with no foot mark whose value is more than *apos-over* times
;; the rectangle's diagonal, and whose feet end in a 1, had its foot mark
;; scanned as that 1 ("101-10" is 10'-10"): the 1 is dropped and the repair
;; logged.  A value still over *impossible* times the diagonal after that
;; cannot be a distance to a corner and is left blank (and logged).  Both
;; are ratios; 1.0 would be the diagonal itself.
(setq altabcdef:*apos-over*  1.05)
(setq altabcdef:*impossible* 1.1)

;; The denominators an inch fraction may have.  A slash-less digit run like
;; "314" is rebuilt as the one fraction over one of these it could be
;; (3/4), so a denominator not listed here is never invented.
(setq altabcdef:*fractions* '(2 4 8 16 32))

;; The correction log writes each repaired value back as feet-inches to the
;; nearest 1/*log-denom* of an inch, reduced (476.75 -> 39'-8 3/4").
;; A whole number, a power of two.
(setq altabcdef:*log-denom* 32)

;; ---- numerical -------------------------------------------------------------
;; These only matter to the solver's arithmetic and should not need
;; touching.

;; Two lengths closer than this are the same length; also the shortest
;; radius the solver will divide by.  In inches.
(setq altabcdef:*fuzz* 1e-9)

;; The least-squares fit: at most *solve-iters* Gauss-Newton steps, done
;; when a step moves the point under *solve-step* inches in both X and Y;
;; a normal-matrix determinant under *solve-singular* (or a linear-seed
;; determinant under *seed-singular*) means the distances do not constrain
;; the point and the fit stops where it is.
(setq altabcdef:*solve-iters*    60)
(setq altabcdef:*solve-step*     1e-7)
(setq altabcdef:*solve-singular* 1e-12)
(setq altabcdef:*seed-singular*  1e-9)

;; The corner self-check accepts a side or diagonal within this many inches
;; of what the entered W and H say it should be.
(setq altabcdef:*frame-tol* 0.001)

;; Two distances fix a point twice over - once each side of the line
;; joining the two corners they were measured from - and both answers fit
;; them EQUALLY well.  From two ADJACENT corners the mirror falls outside
;; the rectangle and the choice is made for us; from two OPPOSITE corners
;; it does not, and the sheet genuinely does not say which of the two the
;; point is.  Such a row is plotted and NAMED on the command line; the
;; mirror has to be this far from the answer to count as a real second
;; possibility rather than rounding.
(setq altabcdef:*mirror-min* 1.0)

;;; --------------------------------------------------------------------------
;;;  String helpers
;;; --------------------------------------------------------------------------

;; Replace every occurrence of the single char OLD with NEW in S.
(defun altabcdef:replace (s old new / out i c)
  (setq out "" i 1)
  (repeat (strlen s)
    (setq c (substr s i 1))
    (setq out (strcat out (if (= c old) new c)))
    (setq i (1+ i)))
  out)

;; Remove every occurrence of the single char CH from S.
(defun altabcdef:strip (s ch)
  (altabcdef:replace s ch ""))

;; Split S on spaces, returning a list of non-empty tokens.
(defun altabcdef:tokens (s / out tok i c)
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
;;;  These helpers repair that noise deterministically before parsing, and
;;;  flag altabcdef:*dirty* so the import can report what it changed.
;;; --------------------------------------------------------------------------

(setq altabcdef:*dirty* nil)   ; set T whenever a value needed cleaning
(setq altabcdef:*fixes* nil)   ; running list of cleanup / warning messages

;; True if S is one or more chars and every char is a digit 0-9.
(defun altabcdef:alldigits (s / ok i a)
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
(defun altabcdef:safechr (n / r a)
  (setq r (vl-catch-all-apply 'chr (list n)))
  (if (or (vl-catch-all-error-p r) (/= (type r) 'STR) (/= (strlen r) 1))
    nil
    (progn
      (setq a (vl-catch-all-apply 'ascii (list r)))
      (if (and (not (vl-catch-all-error-p a)) (= a n)) r nil))))

;; True if S contains only characters a feet-inch value may legitimately hold
;; (digits, space, and  "  '  -  .  / ).  Anything else after scrubbing means a
;; genuinely corrupt cell we should flag rather than silently mis-read.
(defun altabcdef:parseable-p (s / ok i a)
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
;; altabcdef:safechr so a build that can't represent them simply skips that pair:
;;   U+2019 ' / U+2032 prime -> '     U+201D " / U+2033 dbl prime -> "
;;   U+2013 en / U+2014 em dash and CP1252 bytes 150/151 -> -
;; These are high-confidence fixes and are NOT flagged as "needs verifying";
;; only the riskier repairs (fraction rebuild, apostrophe-as-1, split feet)
;; set altabcdef:*dirty*.
(defun altabcdef:scrub (raw / s q)
  (setq s raw)
  (setq s (altabcdef:replace s "_" "-"))    ; underscore read for a dash
  (setq s (altabcdef:replace s "O" "0"))    ; letter O -> zero
  (setq s (altabcdef:replace s "o" "0"))
  (setq s (altabcdef:replace s "I" "1"))    ; letter I / l / bar -> one
  (setq s (altabcdef:replace s "l" "1"))
  (setq s (altabcdef:replace s "|" "1"))
  (setq s (altabcdef:replace s (chr 150) "-"))   ; CP1252 en dash byte
  (setq s (altabcdef:replace s (chr 151) "-"))   ; CP1252 em dash byte
  (if (setq q (altabcdef:safechr 8217)) (setq s (altabcdef:replace s q "'")))
  (if (setq q (altabcdef:safechr 8242)) (setq s (altabcdef:replace s q "'")))
  (if (setq q (altabcdef:safechr 8221)) (setq s (altabcdef:replace s q "\"")))
  (if (setq q (altabcdef:safechr 8243)) (setq s (altabcdef:replace s q "\"")))
  (if (setq q (altabcdef:safechr 8211)) (setq s (altabcdef:replace s q "-")))
  (if (setq q (altabcdef:safechr 8212)) (setq s (altabcdef:replace s q "-")))
  s)

;; TOK is an all-digit run with no slash.  A fraction like 3/4 whose slash was
;; scanned as a 1 becomes 314; because that substitution keeps the length, a
;; valid inch fraction (den in 2..32, 0<num<den) has exactly one reconstruction.
;; Return "num/den" if one is found (scanning candidate slash positions left to
;; right), else nil.
(defun altabcdef:defrac (tok / len k num den ni di best)
  (setq len (strlen tok) k 1 best nil)
  (while (and (<= k len) (null best))
    (if (= (substr tok k 1) "1")
      (progn
        (setq num (substr tok 1 (1- k))
              den (substr tok (1+ k)))
        (if (and (> (strlen num) 0) (> (strlen den) 0)
                 (altabcdef:alldigits num) (altabcdef:alldigits den))
          (progn
            (setq ni (atoi num) di (atoi den))
            (if (and (member di altabcdef:*fractions*) (> ni 0) (< ni di))
              (setq best (strcat num "/" den)))))))
    (setq k (1+ k)))
  best)

;; A fraction OCR-split across tokens: "1 /4", "1/ 4" or "1 / 4" tokenises
;; as ("1" "/4"), ("1/" "4") or ("1" "/" "4"), and the broken "/x" piece
;; would otherwise contribute 0 - losing the fraction, so 4 1/4" reads as
;; 5".  Re-join a token that starts or ends with "/" with its neighbour so
;; the value parses as a real fraction.  (ABCDEF's repair, ported: the same
;; field sheets go through both commands, and 10 cells of the sample sheet
;; are written this way.)
(defun altabcdef:mergefrac (toks / out tok changed)
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
  (if changed (setq altabcdef:*dirty* T))
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
;;;  Only the non-obvious repairs set altabcdef:*dirty* (for the change report).
;;; --------------------------------------------------------------------------

(defun altabcdef:ftin->in (raw maxd / s neg feet ftstr rest inch p dp tok
                                    num den slash df val)
  (setq s (altabcdef:scrub (cal:trim raw)))
  (cond
    ((= s "") nil)                              ; blank cell
    ((not (altabcdef:parseable-p s))               ; corrupt char left over
     (setq altabcdef:*dirty* T) nil)
    (T
      (setq neg nil)
      (if (= (substr s 1 1) "-") (setq neg T s (cal:trim (substr s 2))))
      ;; --- split feet from inches ----------------------------------------
      (setq p (vl-string-search "'" s))
      (cond
        (p                                      ; explicit foot mark
          (setq ftstr (cal:trim (substr s 1 p)))
          (if (vl-string-search " " ftstr) (setq altabcdef:*dirty* T))
          (setq feet (atof (altabcdef:strip ftstr " ")))
          (setq rest (cal:trim (substr s (+ p 2)))))
        ((setq dp (vl-string-search "-" s))     ; no ' but a dash: it is the
          (setq ftstr (altabcdef:strip (cal:trim (substr s 1 dp)) " "))
          (if (vl-string-search " " (cal:trim (substr s 1 dp)))
            (setq altabcdef:*dirty* T))            ; feet/inch separator
          (setq feet (atof ftstr))
          (setq rest (cal:trim (substr s (+ dp 2)))))
        (T (setq feet 0.0 ftstr "" rest s)))    ; inches only
      ;; --- clean the inch remainder --------------------------------------
      (if (= (substr rest 1 1) "-") (setq rest (cal:trim (substr rest 2))))
      (setq rest (altabcdef:strip rest "\""))   ; drop inch marks
      (setq rest (altabcdef:strip rest "'"))    ; and a trailing ' misused as one
      (setq rest (altabcdef:replace rest "-" " "))
      (setq rest (cal:trim rest))
      ;; --- inches: sum whole-number and fraction tokens ------------------
      (setq inch 0.0)
      (foreach tok (altabcdef:mergefrac (altabcdef:tokens rest))
        ;; a slash-less all-digit run of 3+ digits is very likely a fraction
        ;; whose "/" was scanned as a "1" (114 -> 1/4); reconstruct it.
        (if (and (not (vl-string-search "/" tok))
                 (>= (strlen tok) 3)
                 (altabcdef:alldigits tok)
                 (setq df (altabcdef:defrac tok)))
          (setq tok df altabcdef:*dirty* T))
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
      (if (and maxd (null p) (> val (* maxd altabcdef:*apos-over*))
               (> (strlen ftstr) 1)
               (= (substr ftstr (strlen ftstr) 1) "1"))
        (progn
          (setq feet (atof (substr ftstr 1 (1- (strlen ftstr))))
                val  (+ (* feet 12.0) inch)
                altabcdef:*dirty* T)))
      (if neg (setq val (- val)))
      ;; --- final sanity: non-positive or still impossible -> unreadable --
      (if (or (<= val 0.0)
              (and maxd (> val (* maxd altabcdef:*impossible*))))
        (progn (setq altabcdef:*dirty* T) nil)
        val))))

;;; --------------------------------------------------------------------------
;;;  Format inches back to a feet-inch string (for the correction log), to the
;;;  nearest 1/altabcdef:*log-denom*", reduced.  e.g. 476.75 -> 39'-8 3/4"
;;; --------------------------------------------------------------------------

(defun altabcdef:in->ftin (v / neg feet whole n den per s)
  (setq neg (< v 0.0) v (abs v))
  (setq den altabcdef:*log-denom* per (* den 12))
  (setq n (fix (+ (* v den) 0.5)))       ; total 1/den" units, rounded
  (setq feet (fix (/ n per)))            ; per = those units in a foot
  (setq n (- n (* feet per)))
  (setq whole (fix (/ n den)))
  (setq n (- n (* whole den)))           ; leftover 1/den units
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
;;;  fix.
;;;
;;;  TWO distances are crossed EXACTLY instead, and the root nearest the
;;;  seed is taken.  Least-squares cannot be trusted to do it: two circles
;;;  meet at a mirror pair either side of the line joining their centres,
;;;  and ON that line both residual gradients point the same way, so the
;;;  normal matrix is singular and the iteration stops where it started.
;;;  For a pair of OPPOSITE corners the seed - the middle of the frame - is
;;;  exactly on that line, so the old code returned the frame centre itself
;;;  as the answer, with tens of inches of fit error and nothing but the
;;;  RMS column to say so.  Crossing the circles gives a real answer; which
;;;  of the mirror pair it is, only a third distance can say, and the
;;;  command names such a row on the command line.
;;; --------------------------------------------------------------------------

;; Plain 2-D distance between two (x y ...) points.
(defun altabcdef:d2p (p q)
  (sqrt (+ (expt (- (car q) (car p)) 2) (expt (- (cadr q) (cadr p)) 2))))

;; The points at distance RA from CA and RB from CB, as a list of one or
;; two (x y).
;;
;; Quarter-inch distances routinely describe circles that miss each other,
;; or one that swallows the other, by a fraction of an inch.  Rather than
;; give up on those rows, the shortfall is shared equally between the two
;; radii until the circles just touch, and the single touching point comes
;; back - neither distance is called the liar, which is the same principle
;; the least-squares fit works on.
(defun altabcdef:cc-int (ca ra cb rb / d ux uy m h2 h bx by gap)
  (setq d (altabcdef:d2p ca cb))
  (if (< d altabcdef:*fuzz*)
    nil                                  ; the same corner twice
    (progn
      (setq ux (/ (- (car cb) (car ca)) d)
            uy (/ (- (cadr cb) (cadr ca)) d))
      (cond
        ((< (+ ra rb) d)                 ; circles fall short of each other
         (setq gap (- d (+ ra rb))
               ra  (+ ra (* 0.5 gap))
               rb  (+ rb (* 0.5 gap))))
        ((< d (abs (- ra rb)))           ; one circle inside the other
         (setq gap (- (abs (- ra rb)) d))
         (if (> ra rb)
           (setq ra (- ra (* 0.5 gap)) rb (+ rb (* 0.5 gap)))
           (setq ra (+ ra (* 0.5 gap)) rb (- rb (* 0.5 gap))))))
      (setq m  (/ (+ (* d d) (* ra ra) (- (* rb rb))) (* 2.0 d))
            h2 (- (* ra ra) (* m m)))
      (if (< h2 0.0) (setq h2 0.0))      ; only rounding can get here now
      (setq h  (sqrt h2)
            bx (+ (car ca) (* m ux))
            by (+ (cadr ca) (* m uy)))
      (if (< h altabcdef:*fuzz*)
        (list (list bx by))
        (list (list (- bx (* h uy)) (+ by (* h ux)))
              (list (+ bx (* h uy)) (- by (* h ux))))))))

;;; --------------------------------------------------------------------------

(defun altabcdef:solve (corners dists cx cy / n x y i c d dx dy r jx jy f
                             saa sab sbb sac sbc a b cc det xr yr dr
                             jaa jab jbb ga gb ddx ddy res rms iter
                             cands best bd sc)
  (setq n (length corners))
  ;; ---- two distances: cross the circles exactly ---------------------------
  (if (= n 2)
    (setq cands (altabcdef:cc-int (nth 0 corners) (nth 0 dists)
                                  (nth 1 corners) (nth 1 dists))))
  ;; ---- seed --------------------------------------------------------------
  (if cands
    (progn                                   ; the root nearest the seed
      (setq best nil bd nil)
      (foreach c cands
        (setq sc (altabcdef:d2p c (list cx cy)))
        (if (or (null bd) (< sc bd)) (setq bd sc best c)))
      (setq x (car best) y (cadr best)))
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
      (if (> (abs det) altabcdef:*seed-singular*)
        (setq x (/ (- (* sac sbb) (* sbc sab)) det)
              y (/ (- (* saa sbc) (* sab sac)) det))
        (setq x cx y cy)))                    ; degenerate -> centre
    (setq x cx y cy)))                        ; nothing better -> centre
  ;; ---- Gauss-Newton refinement ------------------------------------------
  (setq iter 0)
  (while (< iter altabcdef:*solve-iters*)
    (setq jaa 0.0 jab 0.0 jbb 0.0 ga 0.0 gb 0.0 i 0)
    (while (< i n)
      (setq c (nth i corners) d (nth i dists))
      (setq dx (- x (car c)) dy (- y (cadr c)) r (sqrt (+ (* dx dx) (* dy dy))))
      (if (< r altabcdef:*fuzz*) (setq r altabcdef:*fuzz*))
      (setq jx (/ dx r) jy (/ dy r) f (- r d))
      (setq jaa (+ jaa (* jx jx)) jab (+ jab (* jx jy)) jbb (+ jbb (* jy jy))
            ga (+ ga (* jx f)) gb (+ gb (* jy f)))
      (setq i (1+ i)))
    (setq det (- (* jaa jbb) (* jab jab)))
    (if (< (abs det) altabcdef:*solve-singular*)
      (setq iter altabcdef:*solve-iters*)     ; singular -> stop
      (progn
        (setq ddx (/ (- (- (* ga jbb)) (- (* gb jab)))
                     det)
              ddy (/ (- (- (* jaa gb)) (- (* jab ga)))
                     det))
        ;; ddx = -(ga*jbb - gb*jab)/det ; ddy = -(jaa*gb - jab*ga)/det
        (setq x (+ x ddx) y (+ y ddy))
        (if (and (< (abs ddx) altabcdef:*solve-step*)
                 (< (abs ddy) altabcdef:*solve-step*))
          (setq iter altabcdef:*solve-iters*))))
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
;;;  Did these distances answer once, or twice?
;;; --------------------------------------------------------------------------

;; The mirror of (X Y) in the line through CA and CB - the other point the
;; same two distances describe.  (With three or more distances there is
;; only one answer and none of this applies.)
(defun altabcdef:mirror-pt (x y ca cb / ux uy d tt vx vy)
  (setq ux (- (car cb) (car ca)) uy (- (cadr cb) (cadr ca))
        d  (sqrt (+ (* ux ux) (* uy uy))))
  (if (< d altabcdef:*fuzz*)
    (list x y)                           ; the same corner twice
    (progn
      (setq ux (/ ux d) uy (/ uy d)
            vx (- x (car ca)) vy (- y (cadr ca))
            tt (* 2.0 (+ (* vx ux) (* vy uy))))
      (list (+ (car ca) (- (* tt ux) vx))
            (+ (cadr ca) (- (* tt uy) vy))))))

;; T when exactly two distances placed the point and the mirror answer they
;; also allow lands inside the W x H frame whose top-left corner is
;; (BPX BPY) - i.e. the sheet does not say which of the two it is.
(defun altabcdef:mirror-amb-p (corners x y bpx bpy w h / m)
  (if (/= (length corners) 2)
    nil
    (progn
      (setq m (altabcdef:mirror-pt x y (nth 0 corners) (nth 1 corners)))
      (and (> (sqrt (+ (expt (- (car m) x) 2) (expt (- (cadr m) y) 2)))
              altabcdef:*mirror-min*)
           (>= (car m) bpx) (<= (car m) (+ bpx w))
           (<= (cadr m) bpy) (>= (cadr m) (- bpy h))))))

;;; --------------------------------------------------------------------------
;;;  Drawing helpers
;;; --------------------------------------------------------------------------

;; Make sure a layer exists (create it with COLOR if not).
(defun altabcdef:layer (name color / rec ed flags col fixed)
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

(defun altabcdef:point (pt layer)
  (entmake (list '(0 . "POINT") (cons 8 layer)
                 (cons 10 (list (car pt) (cadr pt) 0.0)))))

(defun altabcdef:circle (pt rad layer)
  (entmake (list '(0 . "CIRCLE") (cons 8 layer)
                 (cons 10 (list (car pt) (cadr pt) 0.0)) (cons 40 rad))))

(defun altabcdef:text (pt hgt str layer)
  (entmake (list '(0 . "TEXT") (cons 8 layer)
                 (cons 10 (list (car pt) (cadr pt) 0.0))
                 (cons 11 (list (car pt) (cadr pt) 0.0))
                 (cons 40 hgt) (cons 1 str) (cons 72 0) (cons 73 0))))

;; Closed 4-vertex polyline A B C D.
(defun altabcdef:frame (a b c d layer)
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
(defun altabcdef:cellstr (v)
  (cond ((null v) "")
        ((= (type v) 'STR) (cal:trim v))
        ((= (type v) 'REAL) (cal:trim (rtos v 2 6)))
        ((= (type v) 'INT) (itoa v))
        (T "")))

(defun altabcdef:xl-cell (sheet r c / res)
  (setq res (vl-catch-all-apply
              '(lambda ()
                 (vlax-variant-value
                   (vlax-get-property
                     (vlax-get-property
                       (vlax-get-property sheet "Cells") "Item" r c)
                     "Text"))) '()))
  (if (vl-catch-all-error-p res) "" (altabcdef:cellstr res)))

;; Classify a header cell (already upper-cased) as 'name / 'a / 'b / 'c / 'd
;; by the words in altabcdef:*hdr-dist* and altabcdef:*hdr-name*: the Nth
;; distance word wins over a name word, and the first match wins.
(defun altabcdef:col-of (up / kind i w)
  (setq kind nil i 0)
  (foreach w altabcdef:*hdr-dist*
    (if (and (null kind) (vl-string-search (strcase w) up))
      (setq kind (cond ((= i 0) 'a) ((= i 1) 'b) ((= i 2) 'c) (T 'd))))
    (setq i (1+ i)))
  (if (null kind)
    (foreach w altabcdef:*hdr-name*
      (if (and (null kind) (vl-string-search (strcase w) up))
        (setq kind 'name))))
  kind)

;; nth (1-based) element of a list, or "" when the index is nil / out of range.
(defun altabcdef:nth-field (lst idx)
  (if (and idx (> idx 0) (<= idx (length lst))) (nth (1- idx) lst) ""))

;; Print the accumulated cleanup / unreadable report (if any).
(defun altabcdef:report-fixes (/ m)
  (if altabcdef:*fixes*
    (progn
      (princ "\n\n--- dirty values cleaned before import ---")
      (foreach m (reverse altabcdef:*fixes*) (princ (strcat "\n" m)))
      (princ "\n  ( * = auto-corrected, ? = unreadable. Verify these! )"))))

;; Parse RAW to inches, logging into altabcdef:*fixes* if the value had to be
;; cleaned up (a risky repair) or could not be read at all.  LABEL identifies
;; the cell in the log, e.g. "P3 / FROM C".  MAXD is the rectangle diagonal.
(defun altabcdef:parse-log (raw label maxd / clean v)
  (setq clean (cal:trim raw))
  (if (= clean "")
    nil                                     ; blank cell: not measured
    (progn
      (setq altabcdef:*dirty* nil)
      (setq v (altabcdef:ftin->in raw maxd))
      (cond
        ((null v)                           ; nonblank but unreadable
         (setq altabcdef:*fixes*
               (cons (strcat "  ? " label ": \"" clean
                             "\"  could not be read - left blank")
                     altabcdef:*fixes*)))
        (altabcdef:*dirty*                     ; cleaned something up
         (setq altabcdef:*fixes*
               (cons (strcat "  * " label ": \"" clean "\"  ->  "
                             (altabcdef:in->ftin v))
                     altabcdef:*fixes*))))
      v)))

;;; --------------------------------------------------------------------------
;;;  Native CSV reading (no Excel needed).  Preferred for .csv because it also
;;;  avoids Excel silently turning cells like "28-11" or "7-0" into dates.
;;; --------------------------------------------------------------------------

;; Split one CSV line into a list of field strings, honouring "quoted" fields
;; and "" escaped quotes.
(defun altabcdef:parse-csv-line (line / fields cur i n c inq)
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

(defun altabcdef:read-csv (file maxd / fp line fields i h up kind
                                    name-c a-c b-c c-c d-c rows nm)
  (setq fp (open file "r"))
  (if (null fp)
    (progn (princ "\n** Could not open the file for reading.") nil)
    (progn
      (setq name-c nil a-c nil b-c nil c-c nil d-c nil)
      ;; --- header row (skip any leading blank lines) --------------------
      (setq line (read-line fp))
      (while (and line (= (cal:trim (altabcdef:strip line (chr 13))) ""))
        (setq line (read-line fp)))
      (if line
        (progn
          (setq fields (altabcdef:parse-csv-line (altabcdef:strip line (chr 13))) i 1)
          (foreach h fields
            (setq up (strcase (cal:trim h)) kind (altabcdef:col-of up))
            (cond ((and (eq kind 'name) (null name-c)) (setq name-c i))
                  ((eq kind 'a) (setq a-c i))
                  ((eq kind 'b) (setq b-c i))
                  ((eq kind 'c) (setq c-c i))
                  ((eq kind 'd) (setq d-c i)))
            (setq i (1+ i)))))
      (if (null name-c) (setq name-c 1))     ; fall back to first column
      ;; --- data rows -----------------------------------------------------
      (setq rows '() altabcdef:*fixes* '())
      (while (setq line (read-line fp))
        (setq line (altabcdef:strip line (chr 13)))
        (if (/= (cal:trim line) "")
          (progn
            (setq fields (altabcdef:parse-csv-line line))
            (setq nm (cal:trim (altabcdef:nth-field fields name-c)))
            (if (/= nm "")
              (setq rows
                (cons (list nm
                    (altabcdef:parse-log (altabcdef:nth-field fields a-c)
                                      (strcat nm " / FROM A") maxd)
                    (altabcdef:parse-log (altabcdef:nth-field fields b-c)
                                      (strcat nm " / FROM B") maxd)
                    (altabcdef:parse-log (altabcdef:nth-field fields c-c)
                                      (strcat nm " / FROM C") maxd)
                    (altabcdef:parse-log (altabcdef:nth-field fields d-c)
                                      (strcat nm " / FROM D") maxd))
                      rows))))))
      (close fp)
      (altabcdef:report-fixes)
      (reverse rows))))

;;; --------------------------------------------------------------------------
;;;  Dispatcher: pick the CSV reader for .csv, else Excel COM automation.
;;; --------------------------------------------------------------------------
(defun altabcdef:read-file (file maxd / ext n)
  (setq n (strlen file) ext "")
  (if (> n 4) (setq ext (strcase (substr file (- n 3)))))
  (if (= ext ".CSV")
    (altabcdef:read-csv file maxd)
    (altabcdef:read-excel file maxd)))

(defun altabcdef:read-excel (file maxd / xl created wbs wb sheet used rng nrows ncols
                                  hdr r c txt up kind name-c a-c b-c d-c c-c
                                  rows nm da db dc dd err m)
  ;; connect to an existing Excel, else start one
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
          (setq name-c nil a-c nil b-c nil c-c nil d-c nil c 1)
          (while (<= c ncols)
            (setq up (strcase (altabcdef:xl-cell sheet 1 c)) kind (altabcdef:col-of up))
            (cond ((and (eq kind 'name) (null name-c)) (setq name-c c))
                  ((eq kind 'a) (setq a-c c))
                  ((eq kind 'b) (setq b-c c))
                  ((eq kind 'c) (setq c-c c))
                  ((eq kind 'd) (setq d-c c)))
            (setq c (1+ c)))
          (if (null name-c) (setq name-c 1))   ; fall back to first column
          ;; --- read the data rows ----------------------------------------
          (setq rows '() altabcdef:*fixes* '() r 2)
          (while (<= r nrows)
            (setq nm (altabcdef:xl-cell sheet r name-c))
            (if (/= nm "")
              (setq rows
                (cons (list nm
                    (if a-c (altabcdef:parse-log (altabcdef:xl-cell sheet r a-c)
                                              (strcat nm " / FROM A") maxd))
                    (if b-c (altabcdef:parse-log (altabcdef:xl-cell sheet r b-c)
                                              (strcat nm " / FROM B") maxd))
                    (if c-c (altabcdef:parse-log (altabcdef:xl-cell sheet r c-c)
                                              (strcat nm " / FROM C") maxd))
                    (if d-c (altabcdef:parse-log (altabcdef:xl-cell sheet r d-c)
                                              (strcat nm " / FROM D") maxd)))
                      rows)))
            (setq r (1+ r)))
          (altabcdef:report-fixes)
          ;; --- close up --------------------------------------------------
          (vl-catch-all-apply '(lambda () (vlax-invoke-method wb "Close" :vlax-false)) '())
          (if created (vl-catch-all-apply '(lambda () (vlax-invoke-method xl "Quit")) '()))
          (vl-catch-all-apply '(lambda () (vlax-release-object wb)) '())
          (vl-catch-all-apply '(lambda () (vlax-release-object wbs)) '())
          (vl-catch-all-apply '(lambda () (vlax-release-object xl)) '())
          (reverse rows))))))

;;; --------------------------------------------------------------------------
;;;  Is the frame really the rectangle it claims to be?
;;;
;;;  This command used to PRINT "all corners 90.00 deg" as a constant,
;;;  which is a claim about the code rather than about the drawing.  ABCDEF
;;;  learned the hard way that the two can part company - two field
;;;  failures were a stale copy whose corner block no longer matched - so
;;;  both sides and diagonals are measured off the corner variables before
;;;  anything is drawn, and the angles are measured off the drawn
;;;  coordinates and printed as measured.
;;; --------------------------------------------------------------------------

;; Verify the named corner variables really form the W x H rectangle they
;; are documented to be: A-B and D-C horizontal sides of length W, A-D and
;; B-C vertical sides of length H, and matching diagonals.  Returns nil
;; when everything is right, else a message naming the first bad
;; measurement.  (Corner order here is the CLOCKWISE one this command
;; uses: A top-left, B top-right, C bottom-right, D bottom-left.)
(defun altabcdef:frame-check (ax ay bx by cx cy dx dy w h / dg chk d bad)
  (setq dg (sqrt (+ (* w w) (* h h))) bad nil)
  (foreach chk (list (list "A-B" ax ay bx by w)
                     (list "D-C" dx dy cx cy w)
                     (list "A-D" ax ay dx dy h)
                     (list "B-C" bx by cx cy h)
                     (list "A-C (diagonal)" ax ay cx cy dg)
                     (list "B-D (diagonal)" bx by dx dy dg))
    (setq d (sqrt (+ (expt (- (nth 3 chk) (nth 1 chk)) 2)
                     (expt (- (nth 4 chk) (nth 2 chk)) 2))))
    (if (and (null bad) (> (abs (- d (nth 5 chk))) altabcdef:*frame-tol*))
      (setq bad (strcat (car chk) " measures " (rtos d 2 2)
                        "\" but should be " (rtos (nth 5 chk) 2 2) "\""))))
  bad)

;; Interior angle in degrees at corner (px py), looking toward (qx qy) and
;; (rx ry).  Measured from the coordinates, NOT assumed.
(defun altabcdef:corner-ang (px py qx qy rx ry / ux uy vx vy cross dot)
  (setq ux (- qx px) uy (- qy py) vx (- rx px) vy (- ry py))
  (setq cross (- (* ux vy) (* uy vx)) dot (+ (* ux vx) (* uy vy)))
  (if (and (< (abs cross) altabcdef:*fuzz*) (< (abs dot) altabcdef:*fuzz*))
    0.0
    (* 180.0 (/ (atan (abs cross) dot) pi))))

;;; --------------------------------------------------------------------------
;;;  Prompt helper: read a feet-inch dimension from the keyboard.
;;; --------------------------------------------------------------------------

;; With BACK non-nil, typing B (Back; Undo works too) returns the
;; symbol AB-BACK so the caller can re-open its previous question.
(defun altabcdef:getdim (prompt back / s v)
  (setq v nil)
  (while (null v)
    (setq s (getstring T (strcat "\n" prompt " (e.g. 20'-6\""
                                 (if back ", B = back" "") "): ")))
    (cond
      ((and back (member (strcase s) '("B" "BACK" "U" "UNDO")))
       (setq v 'AB-BACK))
      (T
       (setq v (altabcdef:ftin->in s nil))
       (if (or (null v) (<= v 0.0))
         (progn (princ "  ** enter a positive dimension, e.g. 20'-6\"")
                (setq v nil))))))
  v)

;;; --------------------------------------------------------------------------
;;;  Main command
;;; --------------------------------------------------------------------------

(defun c:ALTABCDEF (/ *error* undo-open file rows base bpx bpy W H
                    Ax Ay Bx By Cx Cy Dx Dy th mrad
                    good bad r nm din corners dists lbl
                    sol x y rms i tags tg p placed stage done chk angs)
  (vl-load-com)
  (princ (strcat "\nALTABCDEF " *altabcdef-version*))
  ;; the plot is one undo group, so a cancelled run backs out with a
  ;; single U instead of one per entity; the group is only closed if it
  ;; was opened (STANDARDS section 5)
  (defun *error* (msg)
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (setq undo-open nil)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
        (princ (strcat "\nALTABCDEF error: " msg)))
    (if lzd:report (lzd:report "ALTABCDEF" *altabcdef-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "ALTABCDEF" *altabcdef-version*))
  ;; only when undo is recording - _Begin in a drawing with UNDO
  ;; off (bit 1 of UNDOCTL clear) errors out of the command
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn
      (command "_.UNDO" "_Begin")
      (setq undo-open T)))
  ;; ---- the questions, staged: Back (or Undo) at a later prompt
  ;; ---- re-opens the previous one, back to the file dialog itself
  (setq stage 1 done nil)
  (while (not done)
    (cond
      ;; ---- get the spreadsheet ------------------------------------------
      ((= stage 1)
       (setq file (getfiled "Select points spreadsheet"
                            "" altabcdef:*file-types* 16))
       (if (null file)
         (setq done 'quit)
         (progn
           ;; ---- rectangle dimensions ------------------------------------
           (princ "\n--- Rectangle A(top-left) B(top-right) C(bottom-right) D(bottom-left) ---")
           (setq stage 2))))
      ((= stage 2)
       (setq W (altabcdef:getdim "Dimension A-B (width across the top)" T))
       (if (eq W 'AB-BACK) (setq stage 1) (setq stage 3)))
      ((= stage 3)
       (setq H (altabcdef:getdim "Dimension A-D (height down the side)" T))
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
      (setq bpx (car base) bpy (cadr base))
      ;; corner coordinates: A top-left, clockwise, Y up (A-D goes down).
      ;; A-B is horizontal, A-D is vertical -> all four corners are 90 degrees.
      (setq Ax bpx        Ay bpy
            Bx (+ bpx W)  By bpy
            Cx (+ bpx W)  Cy (- bpy H)
            Dx bpx        Dy (- bpy H))
      ;; ---- corner self-check ---------------------------------------------
      ;; refuse to plot anything if the corner variables above no longer
      ;; form the W x H rectangle (this file edited, or a stale copy
      ;; loaded) - a wrong frame silently poisons every solved point.
      (setq chk (altabcdef:frame-check Ax Ay Bx By Cx Cy Dx Dy W H))
      (if chk
        (progn
          (alert (strcat "ALTABCDEF " *altabcdef-version*
                         " - corner layout self-check FAILED:\n\n" chk
                         "\n\nThe loaded copy of ALTABCDEF.lsp appears stale"
                         "\nor hand-edited.  Re-download"
                         "\nlisp/altabcdef/ALTABCDEF.lsp and APPLOAD it"
                         "\nagain.  Nothing was drawn."))
          (princ (strcat "\n** ABORT - corner self-check failed: " chk))
          (princ))
        (progn
      ;; ---- read the sheet ------------------------------------------------
      ;; the rectangle diagonal is the largest distance any point can be from a
      ;; corner; pass it so the parser can spot a foot mark scanned as a digit
      ;; and reject impossible readings.
      (princ "\nReading spreadsheet ... ")
      (setq rows (altabcdef:read-file file (sqrt (+ (* W W) (* H H)))))
      (if (null rows)
        (progn (princ "\nNo usable rows found - nothing plotted.") (princ))
        (progn
          (princ (strcat (itoa (length rows)) " row(s) found."))
          ;; ---- layers & sizing --------------------------------------------
          (altabcdef:layer altabcdef:*frame-layer* altabcdef:*frame-color*)
          (altabcdef:layer altabcdef:*point-layer* altabcdef:*point-color*)
          (altabcdef:layer altabcdef:*label-layer* altabcdef:*label-color*)
          (setq th (/ (max W H) altabcdef:*text-div*))   ; text height
          (if (< th altabcdef:*text-min*) (setq th altabcdef:*text-min*))
          (setq mrad (* th altabcdef:*marker-scale*))    ; marker radius
          ;; ---- draw the rectangle + corner tags ---------------------------
          (altabcdef:frame (list Ax Ay) (list Bx By) (list Cx Cy) (list Dx Dy)
                        altabcdef:*frame-layer*)
          ;; corner letters, offset outward from the corner each sits on
          (setq tags (list (list "A" Ax Ay (- altabcdef:*tag-gap*)
                                            altabcdef:*tag-gap*)
                           (list "B" Bx By altabcdef:*tag-gap*
                                            altabcdef:*tag-gap*)
                           (list "C" Cx Cy altabcdef:*tag-gap*
                                            (- altabcdef:*tag-drop*))
                           (list "D" Dx Dy (- altabcdef:*tag-gap*)
                                            (- altabcdef:*tag-drop*))))
          (foreach tg tags
            (altabcdef:text (list (+ (nth 1 tg) (* th (nth 3 tg)))
                               (+ (nth 2 tg) (* th (nth 4 tg))))
                         (* th altabcdef:*tag-scale*) (car tg)
                         altabcdef:*frame-layer*))
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
            (if (>= (length corners) altabcdef:*min-tapes*)
              (progn
                (setq sol (altabcdef:solve (reverse corners) (reverse dists)
                                        (+ bpx (/ W 2.0)) (- bpy (/ H 2.0))))
                (setq x (car sol) y (cadr sol) rms (caddr sol))
                (altabcdef:point  (list x y) altabcdef:*point-layer*)
                (altabcdef:circle (list x y) mrad altabcdef:*point-layer*)
                (altabcdef:text   (list (+ x (* mrad altabcdef:*label-off*))
                                     (+ y (* mrad altabcdef:*label-off*)))
                               th nm altabcdef:*label-layer*)
                (setq placed (cons (list nm x y rms (length corners)) placed))
                (if (altabcdef:mirror-amb-p (reverse corners) x y bpx bpy W H)
                  (princ (strcat "\n  ! " nm
                                 " : these two distances fit a second point"
                                 " inside the frame just as well"
                                 "\n      (the mirror across the line"
                                 " between the two corners) - a third"
                                 "\n      distance is what tells them"
                                 " apart.")))
                (setq good (1+ good)))
              (progn
                (princ (strcat "\n  ! " nm " : fewer than "
                               (itoa altabcdef:*min-tapes*)
                               " distances given - skipped."))
                (setq bad (1+ bad)))))
          ;; ---- report ------------------------------------------------------
          (princ "\n\n===== ALTABCDEF results (all values in inches) =====")
          (princ "\n  POINT            X          Y      #dims   fit err (RMS)")
          (foreach p (reverse placed)
            (princ (strcat "\n  " (cal:pad (nth 0 p) 14)
                           (altabcdef:padnum (nth 1 p) 10)
                           (altabcdef:padnum (nth 2 p) 11)
                           "    " (itoa (nth 4 p))
                           "      " (rtos (nth 3 p) 2 4) "\"")))
          (princ (strcat "\n-------------------------------------------------"
                         "\n  " (itoa good) " point(s) plotted"
                         (if (> bad 0) (strcat ", " (itoa bad) " skipped") "")
                         "."))
          (princ (strcat "\n  Fit err (RMS) is the leftover rounding error shared"
                         "\n  across the given distances - typically < 0.10\" for"
                         "\n  quarter-inch data.  A large value means a bad reading."))
          ;; ---- confirm the frame is a true rectangle ----------------------
          ;; measure the corner angles from the coordinates that were drawn,
          ;; rather than asserting them - so a future corner-math regression
          ;; shows up right here instead of printing a reassuring constant.
          ;; If the frame LOOKED like a parallelogram, the view was a tilted
          ;; 3D orbit (a flat rectangle foreshortens) - the reset to plan
          ;; below makes it read square.  Geometry is unchanged either way.
          (setq angs (list (altabcdef:corner-ang Ax Ay Bx By Dx Dy)
                           (altabcdef:corner-ang Bx By Ax Ay Cx Cy)
                           (altabcdef:corner-ang Cx Cy Bx By Dx Dy)
                           (altabcdef:corner-ang Dx Dy Ax Ay Cx Cy)))
          (princ (strcat "\n\n  Frame A-B-C-D: " (rtos W 2 2) "\" (A-B) x "
                         (rtos H 2 2) "\" (A-D).  Corner angles, measured"
                         "\n  off the drawn coordinates: "
                         (rtos (nth 0 angs) 2 2) " / " (rtos (nth 1 angs) 2 2)
                         " / " (rtos (nth 2 angs) 2 2) " / "
                         (rtos (nth 3 angs) 2 2) " deg."))
          ;; vl-catch-all-apply takes the argument list as its second argument;
          ;; called with only the lambda it raises "too few arguments" and
          ;; takes the end of the run down with it, which is exactly what
          ;; the catch was there to prevent.
          (vl-catch-all-apply
            '(lambda ()
               (vl-cmdf "_.plan" "_World")
               (vl-cmdf "_.zoom" "_Extents"))
            '())
          (princ "\n  View reset to plan (top) so the rectangle shows square.")
          (princ)))))))
  (if undo-open (command "_.UNDO" "_End"))
  (setq undo-open nil)
  (princ))

;; format a real to 3 decimals, left-padded into WIDTH
(defun altabcdef:padnum (v width / s)
  (setq s (rtos v 2 3))
  (while (< (strlen s) width) (setq s (strcat " " s)))
  s)

(defun c:ALTABCDEFVER ()
  (princ (strcat "\nALTABCDEF " *altabcdef-version*))
  (princ))

;; Quiet inside the whole build: LAZPASS.lsp and
;; CALOFIN-LOADER.lsp set the flag while they load their members,
;; because one file's greeting is a greeting and sixty-three of
;; them is a wall the drafter scrolls past in every drawing they
;; open.  APPLOADed alone the flag is nil and this prints, which
;; is the one time somebody wants to be told.  CALVER reports the
;; whole roster whenever it is asked.
(if (not *calofin-quiet*)
  (princ (strcat "\nALTABCDEF " *altabcdef-version*
                 " loaded.  Type ALTABCDEF to plot points from a spreadsheet.")))
(princ)
