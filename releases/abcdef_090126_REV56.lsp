;;; ==========================================================================
;;; abcdef.lsp  --  Locate measured points inside a rectangle and plot them
;;; --------------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  ABCDEF      read the sheet, place every point, report the fit
;;;            ABCDEFVER   print the loaded version
;;;
;;; Points A B C D sit on the corners of a rectangle:
;;;
;;;        A --------- B         A = top-left      B = top-right
;;;        |           |         C = bottom-left   D = bottom-right
;;;        |           |
;;;        C --------- D         (C sits DIRECTLY BELOW A and D directly
;;;                               below B - the same "Z" reading order as
;;;                               the field sheet, NOT clockwise A-B-C-D)
;;;
;;; The command asks for the two rectangle dimensions A-B (width) and A-C
;;; (height), reads a spreadsheet with the columns
;;;
;;;     POINT NAME | DIST FROM A | DIST FROM B | DIST FROM C | DIST FROM D
;;;
;;; and works out where each named point has to be.  The corners are built
;;; square to the world axes and every one of the four angles is measured
;;; back off the drawn coordinates before anything is plotted, so the frame
;;; the points land in is a true 90-degree rectangle or the run stops.
;;;
;;; HOW MANY TAPES IT TAKES.  Two distances fix a point up to a mirror,
;;; three fix it outright, and the fourth is the cross-check.  A sheet
;;; rarely gives four clean ones, so the leniency is built in:
;;;
;;;   * a row with only TWO distances still plots - the two circles are
;;;     crossed exactly and the root that falls inside the rectangle is
;;;     taken (the mirror root is on the far side of a rectangle side)
;;;   * a row with THREE is least-squares fitted, sharing the leftover
;;;     error across all three
;;;   * a row with FOUR is fitted on all four; if that fit is poor and
;;;     leaving ONE tape out settles the other three, that tape is dropped
;;;     and the report names it
;;;
;;; What it will NOT do is drop a tape it cannot prove is the bad one.
;;; Three tapes that disagree give no evidence about which of them is
;;; wrong - every pair of them fits perfectly - so a poor 3-tape row keeps
;;; all three and is flagged instead of being quietly made to look exact.
;;;
;;; PLACEMENT METHOD, asked per run:
;;;   Auto      the rules above - all tapes, minus a provably bad one
;;;   Furthest  only the two supplied corners furthest apart (widest base)
;;;   Mean      every 2- and 3-tape subset solved, and the answers averaged
;;;   Least     least-squares over every supplied tape, nothing dropped
;;;
;;; CONFIDENCE.  Every point is reported with the number of tapes that
;;; actually placed it, which corners they were, any tape dropped, and a
;;; 0-99 confidence built from four measured things: redundancy, the
;;; leftover fit error, how far the answer moves when any one tape is taken
;;; away, and the angle the tapes cross at.  Nothing in it is a guess.
;;;
;;; INSIDE THE FRAME.  A surveyed pool point belongs inside the rectangle it
;;; was measured from.  A solution that lands outside is pulled back onto
;;; the frame, and the distance it had to be pulled is reported - a small
;;; snap is rounding, a large one means a tape or a dimension is wrong.
;;;
;;; WHAT IT DRAWS.  Each point is an "ab_pt" block on layer POINTS carrying
;;; its sheet label in the number attribute - the same thing a Leica import
;;; produces - so ABHD, CABHD, ABFIND, BPCALLOUT and LHD read this import
;;; with no conversion.  The run ends by offering ABHD the whole set, which
;;; is how a sheet of tape measurements becomes a pool perimeter.
;;;
;;; Distances are entered / stored as architectural feet-inches, e.g.
;;;     12'-3 1/2"      3 1/2"      0'-6"      5'-0 3/4"
;;;
;;; Should a sheet label its bottom corners the other way round (C =
;;; bottom-right, D = bottom-left), the import notices - the distances only
;;; fit the rectangle one way - swaps C and D to match, and says so.
;;;
;;; All geometry is created in inches (1 drawing unit = 1 inch).
;;; ==========================================================================

(vl-load-com)

;; Version banner, shown on load and in every run's output.  When plotted
;; points look wrong, FIRST check the drawing/command line shows the version
;; you think you loaded - two separate field failures turned out to be a
;; stale or hand-edited copy of this file still loaded in AutoCAD.
(setq *abcdef-version* "v5.6")

;;; --------------------------------------------------------------------------
;;;  Tunables
;;; --------------------------------------------------------------------------

;; Quarter-inch field data that was read and typed correctly fits a
;; rectangle well under a tenth of an inch.  These two numbers are where
;; "fits" stops and "check this" starts, in inches of RMS leftover error.
(setq abcdef:*fit-ok*  0.20)   ; at or under this, the tapes agree
(setq abcdef:*fit-bad* 0.50)   ; over this, the point is flagged CHECK

;; How far outside the rectangle a solved point may land and still be
;; treated as rounding to be snapped back, rather than a bad reading.
(setq abcdef:*edge-tol* 1.0)

(setq abcdef:*fuzz* 1e-9)      ; below this, two lengths are the same length

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
;;;  Where a point really is
;;;
;;;  Four tapes to four corners is one measurement more than the geometry
;;;  needs, and in field data that spare one is the whole point: it is what
;;;  turns "here is an answer" into "here is an answer, and here is how much
;;;  the readings argued about it".
;;;
;;;  A row therefore arrives as a small pile of possible answers - every
;;;  pair of tapes, every triple, and the all-four fit.  What follows builds
;;;  that pile, picks from it under the method the user chose, and scores
;;;  the pick.  A tape is only ever discarded on evidence (see abcdef:auto).
;;; --------------------------------------------------------------------------

;; Plain 2-D distance between two (x y ...) points.
(defun abcdef:d2p (p q)
  (sqrt (+ (expt (- (car q) (car p)) 2) (expt (- (cadr q) (cadr p)) 2))))

;; The points at distance RA from CA and RB from CB, as a list of one or
;; two (x y).
;;
;; Quarter-inch tapes routinely describe circles that miss each other, or
;; one that swallows the other, by a fraction of an inch.  Giving up on
;; those rows would throw away most of a real sheet, so instead the
;; shortfall is shared equally between the two radii until the circles just
;; touch, and the single touching point comes back.  Neither tape is called
;; the liar, which is the same principle the least-squares fit works on.
(defun abcdef:cc-int (ca ra cb rb / d ux uy m h2 h bx by gap)
  (setq d (abcdef:d2p ca cb))
  (if (< d abcdef:*fuzz*)
    nil                                  ; the same corner twice: no crossing
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
      (if (< h abcdef:*fuzz*)
        (list (list bx by))
        (list (list (- bx (* h uy)) (+ by (* h ux)))
              (list (+ bx (* h uy)) (- by (* h ux))))))))

;; T when (X Y) is inside RECT - (xmin ymin xmax ymax) - allowing TOL of
;; slop on every side.
(defun abcdef:inside-p (x y rect tol)
  (and (>= x (- (nth 0 rect) tol)) (<= x (+ (nth 2 rect) tol))
       (>= y (- (nth 1 rect) tol)) (<= y (+ (nth 3 rect) tol))))

;; (X Y SNAP) with X Y pulled back onto RECT and SNAP the distance moved.
;; A point measured from four corners of a rectangle belongs inside it; a
;; solution that lands outside is at best rounding and at worst a bad tape,
;; and either way the snap distance is the size of the problem.
(defun abcdef:clamp-in (x y rect / cx cy)
  (setq cx (max (nth 0 rect) (min (nth 2 rect) x))
        cy (max (nth 1 rect) (min (nth 3 rect) y)))
  (list cx cy (abcdef:d2p (list x y) (list cx cy))))

;; The angle in degrees, measured at (X Y), between the lines out to corners
;; CA and CB.  This is the "cut" of the two arcs: near 90 degrees they cross
;; cleanly and a quarter inch of tape error stays a quarter inch on the
;; ground, while near 0 or 180 they cross at a glance and that same quarter
;; inch walks the answer several inches along the crossing.  It is the
;; geometry, not the reading, that makes such a point weak - which is why
;; the confidence score has to see it.
(defun abcdef:cut-ang (x y ca cb / ux uy vx vy la lb dot)
  (setq ux (- (car ca) x) uy (- (cadr ca) y)
        vx (- (car cb) x) vy (- (cadr cb) y)
        la (sqrt (+ (* ux ux) (* uy uy)))
        lb (sqrt (+ (* vx vx) (* vy vy))))
  (if (or (< la abcdef:*fuzz*) (< lb abcdef:*fuzz*))
    0.0
    (progn
      (setq dot (/ (+ (* ux vx) (* uy vy)) (* la lb)))
      (if (> dot  1.0) (setq dot  1.0))
      (if (< dot -1.0) (setq dot -1.0))
      (* 180.0 (/ (atan (sqrt (- 1.0 (* dot dot))) dot) pi)))))

;; The widest cut angle any pair of the used tapes makes at (X Y) - the best
;; crossing the point actually had going for it.
(defun abcdef:best-cut (x y sub / best a i j n)
  (setq best 0.0 n (length sub) i 0)
  (while (< i n)
    (setq j (1+ i))
    (while (< j n)
      (setq a (abcdef:cut-ang x y (cadr (nth i sub)) (cadr (nth j sub))))
      (if (> a 90.0) (setq a (- 180.0 a)))   ; 170 deg cuts as badly as 10
      (if (> a best) (setq best a))
      (setq j (1+ j)))
    (setq i (1+ i)))
  best)

;;; --------------------------------------------------------------------------
;;;  Subsets of the tapes a row supplied
;;; --------------------------------------------------------------------------

;; One row's measured tapes as (INDEX CORNER DIST) triples - index 0-3 for
;; A B C D - with the blank cells left out.  Everything downstream works on
;; these triples, so a row that gave two tapes and a row that gave four take
;; exactly the same path.
(defun abcdef:avail (din pts / out i)
  (setq out '() i 0)
  (repeat 4
    (if (nth i din)
      (setq out (cons (list i (nth i pts) (nth i din)) out)))
    (setq i (1+ i)))
  (reverse out))

;; Every K-element subset of LST, order preserved.  K is 2 or 3 and LST
;; never holds more than four tapes, so the plain recursion is cheap.
(defun abcdef:subsets (lst k)
  (cond ((= k 0) (list '()))
        ((null lst) '())
        (T (append
             (mapcar '(lambda (s) (cons (car lst) s))
                     (abcdef:subsets (cdr lst) (1- k)))
             (abcdef:subsets (cdr lst) k)))))

;; The triples of AV that SUB left out.
(defun abcdef:missing (av sub / out e)
  (setq out nil)
  (foreach e av (if (not (member e sub)) (setq out (cons e out))))
  (if out (reverse out)))

;; "ABD" - the corner letters of a list of triples, in sheet order.
(defun abcdef:letters (sub / s e)
  (setq s "")
  (foreach e (list 0 1 2 3)
    (if (assoc e sub) (setq s (strcat s (nth e '("A" "B" "C" "D"))))))
  (if (= s "") "-" s))

;; Fit one subset of tapes: (X Y RMS RESIDUALS...) in the subset's order.
;;
;; Three or more tapes go to the least-squares fit, which shares the
;; leftover error over all of them.  Exactly two are crossed as circles and
;; the root inside the frame is taken - the mirror root of a pair measured
;; from two rectangle corners sits on the far side of a rectangle side, so
;; there is normally exactly one candidate inside, and the seed only breaks
;; a tie.  Two tapes cross-check nothing, so their RMS is reported as the
;; zero it genuinely is rather than as a fit anyone should be reassured by.
(defun abcdef:fit (sub rect seed / corners dists cands best bd p sc)
  (setq corners (mapcar 'cadr sub) dists (mapcar 'caddr sub))
  (cond
    ((>= (length sub) 3)
     (abcdef:solve corners dists (car seed) (cadr seed)))
    ((= (length sub) 2)
     (setq cands (abcdef:cc-int (nth 0 corners) (nth 0 dists)
                                (nth 1 corners) (nth 1 dists)))
     (if (null cands)
       nil
       (progn
         (setq best nil bd nil)
         (foreach p cands
           (setq sc (+ (if (abcdef:inside-p (car p) (cadr p) rect
                                            abcdef:*edge-tol*)
                         0.0 1.0e6)
                       (abcdef:d2p p seed)))
           (if (or (null bd) (< sc bd)) (setq bd sc best p)))
         (list (car best) (cadr best) 0.0 0.0 0.0))))
    (T nil)))

;; RMS of an already-chosen position against EVERY tape the row supplied.
;; Furthest and Mean place a point from part of the data; this scores that
;; point against all of it, so the four methods stay comparable and a tape
;; the method ignored still gets to object.
(defun abcdef:rms-at (av x y / s n e f)
  (setq s 0.0 n 0)
  (foreach e av
    (setq f (- (abcdef:d2p (list x y) (cadr e)) (caddr e))
          s (+ s (* f f))
          n (1+ n)))
  (if (> n 0) (sqrt (/ s n)) 0.0))

;; Signed leftover error against each tape of AV, in sheet order, for the
;; position (X Y).
(defun abcdef:resids (av x y / out e)
  (setq out '())
  (foreach e av
    (setq out (cons (cons (car e)
                          (- (abcdef:d2p (list x y) (cadr e)) (caddr e)))
                    out)))
  (reverse out))

;; How far the answer moves when any ONE tape of SUB is taken away.
;;
;; This is the disagreement between the tapes said where it matters - in
;; inches on the ground, rather than as a residual that has already been
;; averaged down.  nil for two tapes, because dropping one of those leaves
;; nothing to solve.
(defun abcdef:spread (sub rect seed pt / worst s f d)
  (if (< (length sub) 3)
    nil
    (progn
      (setq worst 0.0)
      (foreach s (abcdef:subsets sub (1- (length sub)))
        (setq f (abcdef:fit s rect seed))
        (if f
          (progn
            (setq d (abcdef:d2p pt (list (car f) (cadr f))))
            (if (> d worst) (setq worst d)))))
      worst)))

;;; --------------------------------------------------------------------------
;;;  The four placement methods
;;;
;;;  Each returns (FIT USED DROPPED), where FIT is what abcdef:fit returns,
;;;  USED the triples that placed the point and DROPPED the supplied ones
;;;  that did not - or nil when the row cannot be placed at all.
;;; --------------------------------------------------------------------------

;; Auto - every tape has a say, minus one that can be PROVEN wrong.
;;
;; With four tapes and a poor fit, leaving each one out in turn is a real
;; experiment: three tapes are still one more than the geometry needs, so if
;; removing a particular tape settles the other three, that tape was the bad
;; one and the evidence is the settling.  With three tapes there is no such
;; evidence - every pair of three fits perfectly, whichever pair you pick -
;; so a poor three-tape row keeps all three and is flagged.  Making it look
;; exact by dropping to a pair would be inventing confidence, which is the
;; one thing a report like this must never do.
;;
;; The experiment has to be DECISIVE as well as successful, and that is not
;; a formality.  A point sitting near a diagonal of the rectangle is barely
;; constrained along that diagonal: the two corners it lies between cross at
;; a glancing angle, so a wrong third tape can drag the answer six inches
;; along the diagonal and still leave a fit of a few hundredths.  Dropping
;; the tape with the lowest leftover error would then throw out a GOOD tape
;; and quietly move the point.  Seen from the numbers, the giveaway is that
;; the best and second-best triples fit equally well - the data cannot tell
;; which tape is wrong.  So a drop needs the runner-up to be clearly worse;
;; when it is not, every tape is kept and the point is graded down instead,
;; which is the same rule the three-tape case already follows.
(defun abcdef:auto (av rect seed / n f rms bs br nr best s trial)
  (setq n (length av) f (abcdef:fit av rect seed))
  (cond
    ((null f) nil)
    ((or (< n 4) (<= (caddr f) abcdef:*fit-ok*))
     (list f av nil))
    (T
     (setq rms (caddr f) bs nil br nil nr nil best nil)
     (foreach s (abcdef:subsets av 3)
       (setq trial (abcdef:fit s rect seed))
       (if trial
         (cond ((or (null br) (< (caddr trial) br))
                (setq nr br br (caddr trial) bs s best trial))
               ((or (null nr) (< (caddr trial) nr))
                (setq nr (caddr trial))))))
     (if (and bs
              (<= br abcdef:*fit-ok*)
              (< br (* 0.5 rms))
              nr
              (> nr (max (* 3.0 br) (+ br 0.25))))   ; the runner-up must lose
       (list best bs (abcdef:missing av bs))
       (list f av nil)))))

;; Furthest - only the two supplied corners furthest apart from each other.
;; On a rectangle that is a diagonal pair whenever both ends were measured,
;; which is the widest base the sheet can offer.
(defun abcdef:furthest (av rect seed / best bd p d f)
  (if (< (length av) 2)
    nil
    (progn
      (setq best nil bd nil)
      (foreach p (abcdef:subsets av 2)
        (setq d (abcdef:d2p (cadr (car p)) (cadr (cadr p))))
        (if (or (null bd) (> d bd)) (setq bd d best p)))
      (setq f (abcdef:fit best rect seed))
      (if f (list f best (abcdef:missing av best))))))

;; Mean - solve every 2- and 3-tape subset on its own and average the
;; answers.  No subset is trusted over any other, so a single bad tape is
;; diluted rather than removed; the report's spread column is what tells
;; you whether the answers being averaged agreed in the first place.
(defun abcdef:mean (av rect seed / subs s f sx sy n x y)
  (if (< (length av) 2)
    nil
    (progn
      (setq subs (abcdef:subsets av 2))
      (if (>= (length av) 3)
        (setq subs (append subs (abcdef:subsets av 3))))
      (setq sx 0.0 sy 0.0 n 0)
      (foreach s subs
        (setq f (abcdef:fit s rect seed))
        (if f (setq sx (+ sx (car f)) sy (+ sy (cadr f)) n (1+ n))))
      (if (= n 0)
        nil
        (progn
          (setq x (/ sx n) y (/ sy n))
          (list (list x y (abcdef:rms-at av x y)) av '()))))))

;; Least - least-squares over every tape supplied, nothing dropped.  This is
;; what every earlier revision of ABCDEF did, kept so an old plot can be
;; reproduced exactly.
(defun abcdef:least (av rect seed / f)
  (setq f (abcdef:fit av rect seed))
  (if f (list f av nil)))

;; Run one row under the chosen method.  Returns
;;   (X Y RMS USED DROPPED SPREAD CUT SNAP URMS)
;; or nil when the row has too little to place.
;;
;; RMS is scored against every tape the sheet gave, URMS against only the
;; tapes that placed the point, and the two are deliberately different
;; numbers.  A row whose bad tape was found and dropped should read as what
;; it is - a well-located point from a sheet with one bad reading in it - so
;; the report shows RMS, which still carries the dropped tape's objection,
;; while the confidence is built on URMS.  Scoring confidence on RMS instead
;; would punish a correctly repaired row exactly as hard as an unrepaired
;; one, leaving no way to tell the two apart in the column that exists to
;; tell them apart.
(defun abcdef:locate (av method rect seed / r f used dropped x y c sp cut)
  (setq r (cond ((= method "Furthest") (abcdef:furthest av rect seed))
                ((= method "Mean")     (abcdef:mean     av rect seed))
                ((= method "Least")    (abcdef:least    av rect seed))
                (T                     (abcdef:auto     av rect seed))))
  (if (null r)
    nil
    (progn
      (setq f (car r) used (cadr r) dropped (caddr r)
            x (car f) y (cadr f))
      ;; the frame has the last word on where a surveyed point can be
      (setq c (abcdef:clamp-in x y rect) x (car c) y (cadr c))
      (setq sp  (abcdef:spread used rect seed (list x y))
            cut (abcdef:best-cut x y used))
      (list x y (abcdef:rms-at av x y) used dropped sp cut (caddr c)
            (abcdef:rms-at used x y)))))

;;; --------------------------------------------------------------------------
;;;  Confidence
;;;
;;;  One number, 1-99, built only from things the sheet actually shows:
;;;
;;;    redundancy  how many tapes had a say.  Four cross-check three, three
;;;                cross-check two, a bare pair cross-checks nothing at all
;;;                and can be exactly wrong without ever looking it.
;;;    fit         the leftover error the tapes could not agree away (RMS).
;;;    spread      how far the answer moves when any one tape is dropped.
;;;    cut         the angle the best pair of tapes crosses at, at the
;;;                point - shallow crossings turn small tape errors into
;;;                large position errors.
;;;
;;;  A dropped tape costs a few points too: the row needed repairing, and a
;;;  repair is a judgement even when the evidence for it was good.
;;; --------------------------------------------------------------------------

(defun abcdef:confidence (used rms spread cut dropped / p)
  (setq p 100.0)
  (cond ((>= used 4) (setq p (- p  0.0)))
        ((= used 3)  (setq p (- p  8.0)))
        (T           (setq p (- p 26.0))))
  (setq p (- p (min 55.0 (* 110.0 rms))))
  (if spread (setq p (- p (min 20.0 (* 12.0 spread)))))
  (cond ((< cut 20.0) (setq p (- p 22.0)))
        ((< cut 35.0) (setq p (- p 10.0)))
        ((< cut 50.0) (setq p (- p  3.0))))
  (if dropped (setq p (- p 6.0)))
  (max 1.0 (min 99.0 p)))

;; The word that goes with a confidence number.
(defun abcdef:grade (pct)
  (cond ((>= pct 90.0) "HIGH")
        ((>= pct 75.0) "GOOD")
        ((>= pct 60.0) "FAIR")
        ((>= pct 40.0) "WEAK")
        (T             "POOR")))


;;; --------------------------------------------------------------------------
;;;  Drawing helpers
;;; --------------------------------------------------------------------------

;; Make sure a layer exists (create it with COLOR if not).
(defun abcdef:layer (name color / rec ed flags col fixed)
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
;;;  Survey points the rest of the toolkit already understands
;;;
;;;  ABHD, CABHD, ADAB, ABFIND, BPCALLOUT and LHD all read a survey the same
;;;  way: an "ab_pt" block INSERT carrying its point number in an attribute,
;;;  or a plain POINT on layer POINTS.  Plotting into that block instead of
;;;  into private ABCDEF-POINTS markers is the whole reason this import can
;;;  become a pool perimeter without a conversion step in between - and it
;;;  is why nothing else drawn here goes on the POINTS layer.
;;; --------------------------------------------------------------------------

(setq abcdef:*point-layer* "POINTS")   ; where the survey points land
(setq abcdef:*point-block* "ab_pt")    ; the block every fitter reads
(setq abcdef:*point-tag*   "number")   ; its point-number attribute

;; Make sure ab_pt exists, building it the way the office template has it
;; when the drawing has never seen one.  (Same definition XFTCONV creates
;; for a Leica import, so a drawing can hold both without a clash.)
(defun abcdef:ensure-block (/ sty)
  (if (not (tblsearch "BLOCK" abcdef:*point-block*))
    (progn
      (setq sty (if (tblsearch "STYLE" "STANDARD")
                  "STANDARD"
                  (getvar "TEXTSTYLE")))
      (entmake (list '(0 . "BLOCK") '(100 . "AcDbEntity") '(8 . "0")
                     '(100 . "AcDbBlockBegin")
                     (cons 2 abcdef:*point-block*) '(70 . 2)
                     '(10 0.0 0.0 0.0)
                     (cons 3 abcdef:*point-block*) '(1 . "")))
      (entmake '((0 . "POINT") (100 . "AcDbEntity") (8 . "0")
                 (100 . "AcDbPoint") (10 0.0 0.0 0.0)))
      (entmake (list '(0 . "ATTDEF") '(100 . "AcDbEntity") '(8 . "0")
                     '(100 . "AcDbText") '(10 1.0 -2.0 0.0) '(40 . 1.0)
                     '(1 . "0") (cons 7 sty)
                     '(100 . "AcDbAttributeDefinition")
                     '(3 . "Type_Point_Number")
                     (cons 2 abcdef:*point-tag*) '(70 . 4)))
      (entmake '((0 . "ENDBLK") (100 . "AcDbEntity") (8 . "0")
                 (100 . "AcDbBlockEnd")))
      (princ (strcat "\n  block \"" abcdef:*point-block*
                     "\" was not in this drawing - created it."))))
  (tblsearch "BLOCK" abcdef:*point-block*))

;; One survey point: ab_pt at PT, its number attribute set to NAME, scaled
;; so the number reads at height TH.
(defun abcdef:insert-pt (pt name th)
  (entmake (list '(0 . "INSERT") '(100 . "AcDbEntity")
                 (cons 8 abcdef:*point-layer*)
                 '(100 . "AcDbBlockReference") '(66 . 1)
                 (cons 2 abcdef:*point-block*)
                 (list 10 (car pt) (cadr pt) 0.0)
                 (cons 41 th) (cons 42 th) (cons 43 th)))
  (entmake (list '(0 . "ATTRIB") '(100 . "AcDbEntity")
                 (cons 8 abcdef:*point-layer*) '(100 . "AcDbText")
                 (list 10 (+ (car pt) th) (- (cadr pt) (* 2.0 th)) 0.0)
                 (cons 40 th) (cons 1 name) '(100 . "AcDbAttribute")
                 (cons 2 abcdef:*point-tag*) '(70 . 0)))
  (entmake (list '(0 . "SEQEND") '(100 . "AcDbEntity")
                 (cons 8 abcdef:*point-layer*))))

;; Every ab_pt INSERT made since MARK (the entlast taken before plotting
;; began, or nil for an empty drawing), as a selection set.
;;
;; Walking forward from a mark is what keeps a second import in the same
;; drawing honest: an "_X" filter on the block name would sweep up the
;; previous survey too and hand ABHD two pools at once.
(defun abcdef:new-points (mark / ss e ed)
  (setq ss (ssadd) e (if mark (entnext mark) (entnext)))
  (while e
    (setq ed (entget e))
    (if (and (= (cdr (assoc 0 ed)) "INSERT")
             (= (strcase (cdr (assoc 2 ed))) (strcase abcdef:*point-block*)))
      (ssadd e ss))
    (setq e (entnext e)))
  ss)

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
                     "Text"))) '()))
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
          (vl-catch-all-apply '(lambda () (vlax-invoke-method wb "Close" :vlax-false)) '())
          (if created (vl-catch-all-apply '(lambda () (vlax-invoke-method xl "Quit")) '()))
          (vl-catch-all-apply '(lambda () (vlax-release-object wb)) '())
          (vl-catch-all-apply '(lambda () (vlax-release-object wbs)) '())
          (vl-catch-all-apply '(lambda () (vlax-release-object xl)) '())
          (reverse rows))))))

;;; --------------------------------------------------------------------------
;;;  Prompt helper: read a feet-inch dimension from the keyboard.
;;; --------------------------------------------------------------------------

;; With BACK non-nil, typing B (Back; Undo works too) returns the
;; symbol AB-BACK so the caller can re-open its previous question.
;;; --------------------------------------------------------------------------
;;;  Asking
;;; --------------------------------------------------------------------------

;; Keyword question in the house format (STANDARDS.md section 1): the
;; bracket text is built from the keyword list so the two cannot drift, and
;; Back / Undo come back as the symbol AB-BACK.
(defun abcdef:askkw (msg kws shown dflt back / v)
  (initget (if dflt 0 (if back 0 1))
           (if back (strcat kws " Back Undo") kws))
  (setq v (getkword (strcat "\n" msg " [" shown
                            (if back "/Back" "") "]"
                            (if dflt (strcat " <" dflt ">") "") ": ")))
  (cond ((member v '("Back" "Undo")) 'AB-BACK)
        ((null v) (if dflt dflt (abcdef:askkw msg kws shown dflt back)))
        (T v)))

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
;;;  The report file
;;;
;;;  The command line report scrolls away, and the numbers behind a plot are
;;;  exactly what gets argued about a week later.  So the same report is
;;;  written to a text file beside the spreadsheet it came from.
;;; --------------------------------------------------------------------------

;; Push one report line onto the accumulating list (newest first).
(defun abcdef:say (rep line)
  (cons line rep))

;; SHEET with its extension replaced by SUFFIX.
(defun abcdef:sibling (sheet suffix / n i cut)
  (setq n (strlen sheet) i n cut nil)
  (while (and (> i 0) (null cut))
    (cond ((= (substr sheet i 1) ".") (setq cut i))
          ((member (substr sheet i 1) '("\\" "/")) (setq i 1)))
    (setq i (1- i)))
  (strcat (if cut (substr sheet 1 (1- cut)) sheet) suffix))

;; Write LINES (newest first, as they were accumulated) to a text file
;; beside SHEET.  Returns the path written, or nil - a report that cannot
;; be saved is worth a note, never worth losing the plot over.
(defun abcdef:write-report (sheet lines / path fp ln)
  (setq path (abcdef:sibling sheet "_ABCDEF_report.txt"))
  (setq fp (vl-catch-all-apply 'open (list path "w")))
  (if (or (vl-catch-all-error-p fp) (null fp))
    nil
    (progn
      (foreach ln (reverse lines) (write-line ln fp))
      (close fp)
      path)))

;;; --------------------------------------------------------------------------
;;;  Handing the survey on to the perimeter fitter
;;; --------------------------------------------------------------------------

;; Pre-select the points just plotted and start ABHD on them.  ABHD reads
;; ab_pt blocks, which is what was drawn, so nothing is converted here - the
;; selection is simply put in front of it and it asks its own questions.
;;
;; ABHD lives in its own file.  Loaded as part of the calofin build it is
;; already here; APPLOADed on its own, abcdef.lsp has no business pretending
;; otherwise, so the absence is reported rather than discovered at the
;; command line.
(defun abcdef:to-abhd (ss / n)
  (setq n (if ss (sslength ss) 0))
  (cond
    ((= n 0)
     (princ "\n  Nothing was plotted, so there is no survey to fit."))
    ((null (boundp 'c:ABHD))
     (princ (strcat "\n  ABHD is not loaded in this drawing, so the points"
                    "\n  were left ready for it instead: they are ab_pt"
                    "\n  blocks on layer " abcdef:*point-layer*
                    ".  APPLOAD abhd.lsp (or the"
                    "\n  whole LAZPASS.lsp build), then run ABHD and"
                    "\n  window the points.")))
    (T
     (princ (strcat "\n  Starting ABHD on the " (itoa n)
                    " point(s) just plotted ..."))
     (sssetfirst nil ss)
     (vl-cmdf "_.ABHD"))))

;;; --------------------------------------------------------------------------
;;;  Main command
;;; --------------------------------------------------------------------------

(defun c:ABCDEF (/ *error* undo-open file rows base bpx bpy W H method
                    Ax Ay Bx By Cx Cy Dx Dy th
                    good bad r nm din d k rr av loc x y rms used dropped
                    sp cut snap urms pct gr rect seed tags tg tx ty placed p
                    flag totn tots n3 swapcd tmp angs chk rstr rl
                    stage done mark ss rep line nby4 nby3 nby2 ndrop
                    nlow path)
  (vl-load-com)
  (princ (strcat "\nABCDEF " *abcdef-version*))
  ;; the plot is one undo group, so a cancelled run backs out with a
  ;; single U instead of one per entity; the group is only closed if it
  ;; was opened (STANDARDS section 5)
  (defun *error* (msg)
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (setq undo-open nil)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
        (princ (strcat "\nABCDEF error: " msg)))
    (princ))
  ;; only when undo is recording - _Begin in a drawing with UNDO
  ;; off (bit 1 of UNDOCTL clear) errors out of the command
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn
      (command "_.UNDO" "_Begin")
      (setq undo-open T)))
  ;; ---- the questions, staged: Back (or Undo) at a later prompt
  ;; ---- re-opens the previous one, back to the file dialog itself
  (setq stage 1 done nil method "Auto")
  (while (not done)
    (cond
      ;; ---- get the spreadsheet ------------------------------------------
      ((= stage 1)
       (setq file (getfiled "Select points spreadsheet"
                            "" "xlsx;xls;xlsm;csv" 16))
       (if (null file)
         (setq done 'quit)
         (progn
           (princ "\n--- Rectangle A(top-left) B(top-right) C(bottom-left) D(bottom-right) ---")
           (setq stage 2))))
      ((= stage 2)
       (setq W (abcdef:getdim "Dimension A-B (width across the top)" T))
       (if (eq W 'AB-BACK) (setq stage 1) (setq stage 3)))
      ((= stage 3)
       (setq H (abcdef:getdim "Dimension A-C (height down the side)" T))
       (if (eq H 'AB-BACK) (setq stage 2) (setq stage 4)))
      ;; ---- how much of each row gets a say -------------------------------
      ((= stage 4)
       (setq method (abcdef:askkw "How should each point be placed?"
                                  "Auto Furthest Mean Least"
                                  "Auto/Furthest/Mean/Least" "Auto" T))
       (if (eq method 'AB-BACK) (setq stage 3) (setq stage 5)))
      ;; ---- where does corner A land? -------------------------------------
      ;; take the pick in WCS so the rectangle is built square to the world
      ;; axes even when the current UCS is rotated (entmake writes WCS).
      (T
       (initget "Back Undo")
       (setq base (getpoint "\nInsertion point for corner A <0,0> [Back]: "))
       (if (= (type base) 'STR) (setq stage 4) (setq done T)))))
  (if (eq done 'quit)
    (progn (princ "\nCancelled.") (princ))
    (progn
      (if base (setq base (trans base 1 0)) (setq base '(0.0 0.0 0.0)))
      (setq bpx (car base) bpy (cadr base))
      ;; Corner coordinates.  A-B runs across the top; C and D sit DIRECTLY
      ;; BELOW A and B (the sheet's "Z" order), so every side is horizontal
      ;; or vertical and all four corners are true right angles:
      ;;    A = (bx, by)       B = (bx+W, by)
      ;;    C = (bx, by-H)     D = (bx+W, by-H)
      (setq Ax bpx        Ay bpy
            Bx (+ bpx W)  By bpy
            Cx bpx        Cy (- bpy H)
            Dx (+ bpx W)  Dy (- bpy H))
      ;; ---- corner self-check ----------------------------------------------
      ;; refuse to plot anything if the corner variables above no longer form
      ;; the W x H rectangle (i.e. this file was edited or a stale copy is
      ;; loaded) - a wrong frame silently poisons every solved point.
      (setq chk (abcdef:frame-check Ax Ay Bx By Cx Cy Dx Dy W H))
      (if chk
        (progn
          (alert (strcat "ABCDEF " *abcdef-version*
                         " - corner layout self-check FAILED:\n\n" chk
                         "\n\nThe loaded copy of abcdef.lsp appears stale or"
                         "\nhand-edited.  Re-download lisp/abcdef/abcdef.lsp"
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
                                         (+ bpx (/ W 2.0)) (- bpy (/ H 2.0))))
                (if rr (setq totn (+ totn rr)))
                (setq rr (abcdef:row-rms din (list Ax Ay) (list Bx By)
                                         (list Dx Dy) (list Cx Cy)
                                         (+ bpx (/ W 2.0)) (- bpy (/ H 2.0))))
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
                "\n     the confidence column below marks the worst points."))
              (alert (strcat
                "ABCDEF " *abcdef-version*
                ": the distances fit the rectangle POORLY\n(average fit error "
                (rtos (/ (if swapcd tots totn) n3) 2 2)
                "\" - quarter-inch data should fit under 0.10\").\n"
                "\nCheck the A-B / A-C dimensions you entered and the"
                "\nsheet's values.  Points ARE plotted, but the report"
                "\ngrades every one of them and flags the doubtful."))))
          ;; ---- layers & sizing --------------------------------------------
          (abcdef:layer "ABCDEF-FRAME"  1)     ; red
          (abcdef:layer "ABCDEF-WARN"   1)     ; red - notes on doubtful fits
          (abcdef:layer abcdef:*point-layer* 2) ; yellow - the survey itself
          (abcdef:ensure-block)
          (setq th (/ (max W H) 120.0))        ; text height
          (if (< th 0.5) (setq th 0.5))
          ;; ---- draw the rectangle + corner tags ---------------------------
          ;; perimeter order TL -> TR -> BR -> BL, by position (so the frame
          ;; stays a rectangle no matter which naming the sheet used).
          (abcdef:frame (list bpx bpy)
                        (list (+ bpx W) bpy)
                        (list (+ bpx W) (- bpy H))
                        (list bpx (- bpy H))
                        "ABCDEF-FRAME")
          ;; corner name tags, offset outward from whichever corner each
          ;; letter ended up on.
          (setq tags (list (list "A" Ax Ay) (list "B" Bx By)
                           (list "C" Cx Cy) (list "D" Dx Dy)))
          (foreach tg tags
            (setq tx (if (> (cadr tg)  (+ bpx (* 0.5 W))) th (* -1 th))
                  ty (if (> (caddr tg) (- bpy (* 0.5 H))) th (* -1.6 th)))
            (abcdef:text (list (+ (cadr tg) tx) (+ (caddr tg) ty))
                         (* th 1.4) (car tg) "ABCDEF-FRAME"))
          ;; ---- plot each measured point -----------------------------------
          ;; RECT is the frame every solution is held inside; SEED is its
          ;; middle, which is where an ambiguous two-tape crossing starts
          ;; looking from.  MARK is the drawing's last entity before any
          ;; point exists, so the ABHD handoff can pick out exactly the
          ;; points this run made.
          (setq rect (list bpx (- bpy H) (+ bpx W) bpy)
                seed (list (+ bpx (/ W 2.0)) (- bpy (/ H 2.0)))
                mark (entlast))
          (setq good 0 bad 0 placed '()
                nby4 0 nby3 0 nby2 0 ndrop 0 nlow 0)
          (foreach r rows
            (setq nm (car r) din (cdr r))
            (setq av (abcdef:avail din (list (list Ax Ay) (list Bx By)
                                             (list Cx Cy) (list Dx Dy))))
            (setq loc (if (>= (length av) 2)
                        (abcdef:locate av method rect seed)))
            (if loc
              (progn
                (setq x    (nth 0 loc) y       (nth 1 loc)
                      rms  (nth 2 loc) used    (nth 3 loc)
                      dropped (nth 4 loc)
                      sp   (nth 5 loc) cut     (nth 6 loc)
                      snap (nth 7 loc) urms    (nth 8 loc))
                (setq pct (abcdef:confidence (length used) urms sp cut dropped)
                      gr  (abcdef:grade pct))
                ;; signed leftover error against each supplied tape, in sheet
                ;; order A B C D ("--" = not measured) - what each tape still
                ;; disagrees with after the point was placed
                (setq rl (abcdef:resids av x y) rstr "")
                (foreach k '(0 1 2 3)
                  (setq rstr (strcat rstr
                    (abcdef:pad (if (assoc k rl)
                                  (abcdef:signres (cdr (assoc k rl)))
                                  "  --")
                                7))))
                (abcdef:insert-pt (list x y) nm th)
                ;; a doubtful point says so in the drawing too, not only in
                ;; the report that scrolls away
                (setq flag "")
                (if (> rms abcdef:*fit-bad*) (setq flag "  **CHECK"))
                (if (> snap 0.001)
                  (setq flag (strcat flag "  (snapped "
                                     (rtos snap 2 2) "\" into frame)")))
                (if dropped
                  (setq flag (strcat flag "  (dropped "
                                     (abcdef:letters dropped) ")")))
                ;; four tapes that argue, with no one of them provably the
                ;; liar, is a different problem from a bad reading and gets
                ;; said out loud rather than hidden behind the grade
                (if (and (null dropped) (= (length used) 4)
                         (> rms abcdef:*fit-ok*))
                  (setq flag (strcat flag "  (tapes disagree, none provably wrong)")))
                (if (or (> rms abcdef:*fit-bad*) (< pct 60.0)
                        (> snap abcdef:*edge-tol*))
                  (progn
                    (setq nlow (1+ nlow))
                    (abcdef:text (list (+ x (* th 0.6)) (+ y (* th 0.6)))
                                 th (strcat nm " " gr) "ABCDEF-WARN")))
                (cond ((>= (length used) 4) (setq nby4 (1+ nby4)))
                      ((= (length used) 3)  (setq nby3 (1+ nby3)))
                      (T                    (setq nby2 (1+ nby2))))
                (if dropped (setq ndrop (1+ ndrop)))
                (setq placed (cons (list nm x y (length used) (length av)
                                         (abcdef:letters used) rms sp cut
                                         pct gr flag rstr)
                                   placed))
                (setq good (1+ good)))
              (progn
                (princ (strcat "\n  ! " nm
                               " : fewer than 2 distances given - skipped."))
                (setq bad (1+ bad)))))
          ;; ---- report ------------------------------------------------------
          ;; built as a list of lines so the same text goes to the command
          ;; line and to the file beside the sheet
          (setq rep '())
          (setq rep (abcdef:say rep (strcat "===== ABCDEF " *abcdef-version*
                                            " results (inches) =====")))
          (setq rep (abcdef:say rep (strcat "  sheet  : " file)))
          (setq rep (abcdef:say rep (strcat "  method : " method)))
          (setq rep (abcdef:say rep (strcat "  frame  : " (rtos W 2 2)
                                            "\" (A-B) x " (rtos H 2 2)
                                            "\" (A-C)"
                                            (if swapcd
                                              ", C/D read swapped" ""))))
          (setq rep (abcdef:say rep ""))
          (setq rep (abcdef:say rep
            (strcat "  POINT            X          Y     TAPES  USED"
                    "   FIT     SPREAD  CUT    CONF"
                    "      err vs A      B      C      D")))
          (foreach p (reverse placed)
            (setq rep (abcdef:say rep (strcat
              "  " (abcdef:pad (nth 0 p) 14)
              (abcdef:padnum (nth 1 p) 10)
              (abcdef:padnum (nth 2 p) 11)
              "   " (itoa (nth 3 p)) " of " (itoa (nth 4 p))
              "  " (abcdef:pad (nth 5 p) 6)
              (abcdef:pad (strcat (rtos (nth 6 p) 2 3) "\"") 8)
              (abcdef:pad (if (nth 7 p)
                            (strcat (rtos (nth 7 p) 2 2) "\"") "   --") 8)
              (abcdef:pad (strcat (rtos (nth 8 p) 2 0) "d") 7)
              (abcdef:pad (strcat (rtos (nth 9 p) 2 0) "% " (nth 10 p)) 10)
              (nth 12 p) (nth 11 p)))))
          (setq rep (abcdef:say rep
            "-------------------------------------------------------------"))
          (setq rep (abcdef:say rep (strcat
            "  " (itoa good) " point(s) plotted"
            (if (> bad 0) (strcat ", " (itoa bad) " skipped (under 2 tapes)")
              "") ".")))
          (setq rep (abcdef:say rep (strcat
            "  placed by 4 tapes: " (itoa nby4)
            "   by 3: " (itoa nby3)
            "   by 2: " (itoa nby2)
            (if (> ndrop 0)
              (strcat "   (" (itoa ndrop) " with one tape dropped)") ""))))
          (setq rep (abcdef:say rep (strcat
            "  " (itoa nlow) " point(s) want checking"
            " (FIT over " (rtos abcdef:*fit-bad* 2 2)
            "\", confidence under 60%, or snapped over "
            (rtos abcdef:*edge-tol* 2 2) "\").")))
          (setq rep (abcdef:say rep ""))
          (setq rep (abcdef:say rep
            "  TAPES  how many of the four distances the sheet gave."))
          (setq rep (abcdef:say rep
            "  USED   which corners actually placed the point.  Under Auto a"))
          (setq rep (abcdef:say rep
            "         tape is only left out when four were given and leaving"))
          (setq rep (abcdef:say rep
            "         that one out settles the other three: three tapes that"))
          (setq rep (abcdef:say rep
            "         disagree never say which of them is the wrong one, so"))
          (setq rep (abcdef:say rep
            "         they are all kept and the point is graded down instead."))
          (setq rep (abcdef:say rep
            "  FIT    RMS leftover error against every tape the sheet gave."))
          (setq rep (abcdef:say rep
            "  SPREAD how far the point moves if any one tape is dropped."))
          (setq rep (abcdef:say rep
            "  CUT    angle the best pair of tapes crosses at, at the point."))
          (setq rep (abcdef:say rep
            "  CONF   all four of those together, 1-99%.  Two tapes cross-"))
          (setq rep (abcdef:say rep
            "         check nothing, so a 2-tape point is capped well short"))
          (setq rep (abcdef:say rep
            "         of certainty however neatly the circles crossed."))
          ;; ---- confirm the frame really is a rectangle --------------------
          ;; measure the corner angles from the coordinates that were drawn,
          ;; rather than asserting them - so a future corner-math regression
          ;; shows up right here instead of printing a reassuring constant.
          (setq angs (list
            (abcdef:corner-ang bpx bpy (+ bpx W) bpy bpx (- bpy H))
            (abcdef:corner-ang (+ bpx W) bpy bpx bpy (+ bpx W) (- bpy H))
            (abcdef:corner-ang (+ bpx W) (- bpy H) (+ bpx W) bpy bpx (- bpy H))
            (abcdef:corner-ang bpx (- bpy H) bpx bpy (+ bpx W) (- bpy H))))
          (setq rep (abcdef:say rep ""))
          (setq rep (abcdef:say rep (strcat
            "  Frame corner angles, measured off the drawn coordinates: "
            (rtos (nth 0 angs) 2 2) " / " (rtos (nth 1 angs) 2 2) " / "
            (rtos (nth 2 angs) 2 2) " / " (rtos (nth 3 angs) 2 2) " deg."
            "  Every point above is inside it.")))
          (foreach line (reverse rep) (princ (strcat "\n" line)))
          ;; ---- the same thing, on disk ------------------------------------
          (setq path (abcdef:write-report file rep))
          (princ (if path
                   (strcat "\n\n  Report saved: " path)
                   "\n\n  ** the report file could not be written (read-only folder?)"))
          ;; vl-catch-all-apply takes the argument list as its second argument;
          ;; called with only the lambda it raises "too few arguments" and
          ;; takes the end of the run down with it, which is exactly what
          ;; the catch was there to prevent.
          (vl-catch-all-apply
            '(lambda ()
               (vl-cmdf "_.plan" "_World")
               (vl-cmdf "_.zoom" "_Extents"))
            '())
          (princ "\n  View reset to plan (top).")
          ;; ---- on to the pool perimeter -----------------------------------
          (setq ss (abcdef:new-points mark))
          (princ (strcat "\n\n  The " (itoa good)
                         " point(s) are ab_pt blocks on layer "
                         abcdef:*point-layer* ", numbered from the sheet."))
          (if (and (> good 0)
                   (= "Yes" (abcdef:askkw
                              "Fit a pool perimeter through these points now?"
                              "Yes No" "Yes/No" "Yes" nil)))
            (abcdef:to-abhd ss)
            (princ "\n  Left as points - run ABHD (or CABHD) when ready."))
          (princ)))))))
  (if undo-open (command "_.UNDO" "_End"))
  (setq undo-open nil)
  (princ))

;; Print the loaded version.
(defun c:ABCDEFVER ()
  (princ (strcat "\nABCDEF " *abcdef-version* " (abcdef.lsp)"))
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

(princ (strcat "\nABCDEF.lsp rev " *abcdef-version*
               " loaded.  Type ABCDEF to plot points from a spreadsheet."))
(princ)
