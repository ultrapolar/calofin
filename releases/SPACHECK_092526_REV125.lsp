;;; ======================================================================
;;; SPACHECK.lsp  --  audit a finished spa drawing against what SPA draws
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  SPACHECK        guided review of everything it flags
;;;            SPACHECKSCAN    the same audits, read-only
;;;            LITESPACHECKSCAN  the scan minus the dimension audit
;;;            SPACHECKVER     print the loaded version
;;;            SPACHECKRESCUE  put back every colour, remove the markers
;;;            TUTORIALSPACHECK   the checklist, a worked demo, or both
;;; ======================================================================
;;;
;;;  Highlight the spa drawing TOGETHER WITH its "Spa Cover Details"
;;;  block; SPACHECK reads the block for the grade and taper, then holds
;;;  the drawing against the rules SPA.LSP builds to.  Every audit is
;;;  derived from what SPA actually draws, so a drawing SPA produced
;;;  passes and a hand-edited one shows exactly where it drifted.
;;;
;;;  THE CHECKS
;;;
;;;   1. SPA COVER DETAILS BLOCK.  One must be in the selection, with a
;;;      readable TAPER tag; GRADE may be absent (Standard is assumed,
;;;      as SPA assumes it).  Everything in section 5 depends on it.
;;;
;;;   2. THE COVER OUTLINE.  Exactly one, on layer COVER, and it must be
;;;      a single CLOSED bounded entity -- one LWPOLYLINE, or a CIRCLE /
;;;      ELLIPSE for a round spa.  Loose lines and arcs are the old
;;;      pre-bounded output and are reported as such.
;;;
;;;   3. THE WATER'S EDGE OUTLINE.  Optional -- a drawing may show one
;;;      outline only.  When present it must also be a single closed
;;;      entity, on layer POOL, drawn dashed, and it must lie INSIDE the
;;;      cover: the cover is always the larger of the two.
;;;
;;;   4. THE DIMENSIONS.  First the roster-wide verdict: every
;;;      dimension must sit on the DIMENSION layer, and any that do
;;;      not are counted, their layers named, and CDIM suggested to
;;;      move them -- the one dimension check LITESPACHECKSCAN keeps.
;;;      Then every dimension is checked for
;;;        - the right layer (DIMENSION),
;;;        - the right style: STANDARD INCHES for the cover's, and
;;;          STANDARD INCHES 0.5 for the water's edge's,
;;;        - agreement with the geometry: a dimension whose measurement
;;;          does not match what it spans is reported with both numbers,
;;;        - definition points that actually sit on the outline.
;;;      Then the roster: the two overalls must be present and must read
;;;      the cover's true size; each must carry its Cover Size / Water's
;;;      Edge note; with both outlines drawn there must be an Overlap
;;;      dimension and it must read the true lap; and the overall
;;;      standoffs must be SPA's (2 ft above, 3 ft to the left).
;;;
;;;   5. THE HINGES.  Hinges are the LINEs on layer COVER (the outline
;;;      itself is a polyline, so the two never confuse).  Checked
;;;      against the block's grade and taper:
;;;        - the piece count must be one the taper allows,
;;;        - no piece wider than the foam width,
;;;        - no hinge longer than the foam length,
;;;        - the fold/velcro arrangement must match the Hinge
;;;          Arrangement Chart for that piece count,
;;;        - every hinge must carry its label on layer TEXT.
;;;      Hardware called for by the longest hinge -- velcro hinges,
;;;      double C channel, hold down kit -- is reported as advice.
;;;
;;;   6. FEET AND INCHES.  Every text box in the selection -- TEXT,
;;;      MTEXT and the ATTRIB values on blocks -- must state its
;;;      inches wherever it states feet: 5' is flagged, 5'-0", 3'-2"
;;;      and a plain 40" are fine.  A feet mark is an apostrophe
;;;      straight after a digit, so "Water's Edge" is prose and never
;;;      flagged.  LITESPACHECKSCAN keeps this one.
;;;
;;;   7. THE TECH TITLE DATE.  The Date attribute of the "Tech Title"
;;;      block must read TODAY, written MM/DD/YYYY -- a sheet going
;;;      out under an old date is the mistake this catches.  SPACHECK
;;;      does not just report a wrong one: it WRITES TODAY'S OVER IT
;;;      in that same form, keeping any "Date =" label in front of it,
;;;      and the report says what it found and what it set.  The scans
;;;      write nothing and say NEEDS UPDATING instead.  The block is
;;;      looked for in the selection and then across the drawing;
;;;      with none in reach the report says the date was not checked
;;;      rather than flagging it.  With several, the one nearest the
;;;      spa is read, named, and never written.  LITESPACHECKSCAN
;;;      keeps this one.
;;;
;;;   8. THE TITLE BLOCK.  Everything on the border layer is measured
;;;      together, so a frame drawn as one polyline and one drawn as
;;;      four lines -- corners closed or left a little open -- both
;;;      measure the same; one frame per sheet: with several sheets,
;;;      the one around or nearest the spa.  A border not in the
;;;      selection is looked for in the space the drafter is working in
;;;      only (model space from a layout viewport), unlike the Tech
;;;      Title in 7, which may live in paper space.  A spa
;;;      sheet's title block is exactly 0.6x the liner block: the liner
;;;      nominal is 704 x 543.625, so the spa nominal is 422.4 x
;;;      326.175.  Anything else is reported with the factor it actually
;;;      came out at, and a border out of proportion is reported
;;;      separately as STRETCHED.
;;;
;;;   9. A SPACHECK REPORT (MTEXT) is placed to the RIGHT of the
;;;      drawing, sized to scale with it: a large title, the date and
;;;      version under it, an ALL CLEAR / problem-count verdict, then
;;;      the SPA-specific findings under underlined section headings.
;;;      The mechanical per-dimension audit (each dimension's layer,
;;;      style and span agreement) is set apart in a DIMENSION AUDIT
;;;      column to the RIGHT of the main sheet, since DIMCHECK covers
;;;      the same ground; LITESPACHECKSCAN skips that audit entirely,
;;;      for drawings DIMCHECK already went over.  Problems in RED at
;;;      full size, advice in CYAN, all-clear in green at 75%.
;;;
;;;  Every size and standoff above is measured along the COVER'S OWN
;;;  axes, read off the drawing (spachk:cover-frame): SPA draws along
;;;  the current UCS, so a spa drawn in a turned UCS is turned in World,
;;;  and the reviewer's UCS plays no part.  The title-block border is
;;;  measured in its own frame the same way.  A cover or border square
;;;  to World is measured exactly as it always was.
;;;
;;;  SPACHECK walks whatever it flagged one item at a time -- greying
;;;  the rest out, zooming to each, and colouring the ones you confirm
;;;  are wrong -- while SPACHECKSCAN runs the identical audits and
;;;  writes nothing but the report.  SPACHECKRESCUE puts every colour
;;;  back and removes the markers.
;;; ======================================================================

;;; -------------------- version -----------------------------------------
;;;  The banner form tools/release_lisp.py reads (lowercase name, "v",
;;;  one dot).  Bump it with every change and regenerate releases/.

(setq *spacheck-version* "v1.25")

;; vlax-* is used for bounding boxes, so load Visual LISP once here
;; rather than inside a command body.
(vl-load-com)

;;; ======================================================================
;;;  TUNABLES -- every value SPACHECK reads that someone might want to
;;;  change lives in this block, and nowhere else in the file.
;;;
;;;  How to change one: edit the value, save, and APPLOAD the file
;;;  again.  To try a value for one session only, type the setq at the
;;;  command line -- e.g. (setq spachk:*meas-tol* 0.125) -- because
;;;  every knob is read when the command runs, not when the file loads.
;;;
;;;  Units: distances are drawing units (1 unit = 1 inch on the shop's
;;;  sheets); colours are ACI numbers (1 red, 2 yellow, 3 green, 4 cyan,
;;;  5 blue, 6 magenta, 7 white, 8 grey, 256 ByLayer).
;;;
;;;  Several of these are SPA's values, not SPACHECK's own: the audit
;;;  measures a drawing against what SPA draws, so if SPA moves, the
;;;  matching knob here moves with it or the audit reports the drawing
;;;  wrong.  Each one says so.
;;; ----------------------------------------------------------------------

;; -- layers ------------------------------------------------------------

;; Layers SPA draws on -- the audit is only as right as these are.
(setq spachk:*lay-cover*  "COVER")      ; the cover outline and the hinges
(setq spachk:*lay-water*  "POOL")       ; the water's edge outline
(setq spachk:*lay-dim*    "DIMENSION")  ; every dimension
(setq spachk:*lay-text*   "TEXT")       ; the hinge labels
(setq spachk:*lay-notes*  "SPA-NOTES")  ; corner letters, mode note, report

;; CDIM is the command that moves stray dimensions onto *lay-dim*, and
;; is what the report tells you to run when it finds any.
(setq spachk:*dimfix-cmd* "CDIM")

;; The sheet's title block, and the attribute in it carrying the date.
;; This is the Tech Title BLOCK, not the drawn border section 7 checks.
(setq spachk:*techtitle-block* "Tech Title")  ; spaces optional in the name
(setq spachk:*date-tag*        "Date")

;; Dimension styles, one per outline (SPA's spa:*ds-cover* / *ds-water*).
(setq spachk:*ds-cover*   "STANDARD INCHES")
(setq spachk:*ds-water*   "STANDARD INCHES 0.5")

;; The notes SPA stacks under an overall's measurement.
(setq spachk:*sfx-cover*  "Cover Size")
(setq spachk:*sfx-water*  "Water's Edge")
(setq spachk:*sfx-lap*    "Overlap")

;; SPA's standoffs (spa:*topoff* / *dimoff* / *flatoff*), and how far a
;; dimension line may sit from them before it is worth reporting.
(setq spachk:*topoff*     24.0)   ; 2 ft: cover -> the TOP overall dim
(setq spachk:*dimoff*     36.0)   ; 3 ft: cover -> the LEFT overall dim
(setq spachk:*off-tol*    2.0)    ; inches of slack on either standoff

;; The block SPA reads the grade and taper out of.
(setq spachk:*details-block* "Spa Cover Details")

;; TITLE BLOCK.  The liner block is linfincheck's nominal border
;; (*lfc-border-w* / *lfc-border-h*); a spa sheet's title block is
;; exactly this fraction of it.
(setq spachk:*liner-w*    704.0)     ; 58'-8"     in drawing units
(setq spachk:*liner-h*    543.625)   ; 45'-3 5/8" in drawing units
(setq spachk:*title-frac* 0.6)       ; spa title block = 0.6 x the liner
(setq spachk:*border-layer* "border")
(setq spachk:*border-tol* 0.005)     ; 0.5% slack on the factor and the aspect

;; How close a dimension's measurement must be to the geometry it spans,
;; and how close a definition point must sit to the outline.
(setq spachk:*meas-tol*   0.0625)    ; 1/16" -- a fractional dim rounds
(setq spachk:*pt-tol*     1.0e-4)

;; -- marking and report colours ----------------------------------------

(setq spachk:*grey-color*  8)        ; ACI: reserved for fading, unused today
(setq spachk:*flag-color*  1)        ; ACI: what you confirmed is wrong (red)
(setq spachk:*advice-color* 4)       ; ACI: advice, not a failure (cyan)
(setq spachk:*green-scale* 0.75)     ; all-clear text height vs the red

;; The layer the report MTEXT goes on, created on first use; the colour
;; applies only then, so a layer already in the drawing keeps its own.
(setq spachk:*report-layer* "SPACHECK-REPORT")
(setq spachk:*report-color* 3)       ; ACI (green)
(setq spachk:*report-chars* 48.0)    ; report column width, in text heights
(setq spachk:*zoom-margin* 0.75)   ; empty space around a zoomed item


;; Foam sheets, copied from SPA (spa:*foamtab*) so the audit measures
;; against the same rules the drawing was built to:
;;   (grade taper ((foamWidth . foamLength) ...) (piece counts, 5 = 5+))
(setq spachk:*foamtab*
  (list
    (list "ECONOMY"     "3-2"   (list (cons 48.0 96.0))                    (list 2))
    (list "STANDARD"    "3-2"   (list (cons 48.0 144.0) (cons 49.5 102.0)) (list 2))
    (list "STANDARD"    "4-2"   (list (cons 48.0 96.0)  (cons 49.5 102.0)) (list 2 3 4))
    (list "STANDARD"    "4-3"   (list (cons 48.0 144.0))                   (list 2 3 4))
    (list "STANDARD"    "5-3"   (list (cons 48.0 96.0))                    (list 2 3 4 5))
    (list "STANDARD"    "5-4"   (list (cons 48.0 96.0))                    (list 2 3 4 5))
    (list "STANDARD"    "3-3"   (list (cons 48.0 144.0))                   (list 2 3 4 5))
    (list "ULTRA"       "3-2"   (list (cons 48.0 144.0))                   (list 2))
    (list "ULTRA"       "4-3"   (list (cons 48.0 96.0))                    (list 2 3 4))
    (list "ULTRA"       "3-3"   (list (cons 48.0 144.0))                   (list 2 3 4 5))
    (list "THERMOLIGHT" "1-3/8" (list (cons 53.0 nil))                     (list 2 3 4 5))))

;; Hardware called for by the LONGEST hinge, per grade:
;;   (grade velcro doubleC holddown), each (OVER n) | (ALWAYS) | (NEVER)
;;   | (REQUEST)
(setq spachk:*hardtab*
  (list
    (list "ECONOMY"     '(REQUEST)    '(REQUEST)    '(REQUEST))
    (list "STANDARD"    '(OVER 120.0) '(OVER 108.0) '(OVER 120.0))
    (list "ULTRA"       '(OVER 108.0) '(NEVER)      '(OVER 96.0))
    (list "THERMOLIGHT" '(ALWAYS)     '(NEVER)      '(NEVER))))

;; A piece count this high or higher is the table's top row ("5 = 5+").
(setq spachk:*hallow-max* 5)       ; pieces

;; -- reading the drawing -----------------------------------------------

;; The details block's two attribute tags, and how their values are
;; recognised.  GRADE and TAPER are matched as SUBSTRINGS of the
;; upper-cased value, first match winning, so "Ultra FRP" reads as
;; ULTRA; a value matching nothing takes the default grade.  Every
;; canonical name here must appear in *foamtab* and *hardtab* above, or
;; the audit has a grade it can recognise but not measure against.
(setq spachk:*grade-tag*  "GRADE")
(setq spachk:*taper-tag*  "TAPER")
(setq spachk:*grade-words*
      '(("ECON"   . "ECONOMY")
        ("ULTRA"  . "ULTRA")
        ("FRP"    . "ULTRA")
        ("THERMO" . "THERMOLIGHT")))
(setq spachk:*grade-default* "STANDARD")  ; the grade a value matching nothing takes
;; ...and the taper vocabulary, matched the same way; an unrecognised
;; taper measures against no foam row at all rather than the wrong one.
(setq spachk:*taper-words*
      '(("3-2" . "3-2") ("4-2" . "4-2") ("4-3" . "4-3")
        ("5-3" . "5-3") ("5-4" . "5-4") ("3-3" . "3-3")
        ("3/8" . "1-3/8")))

;; The short grade names the report prints, keyed by the canonical name.
(setq spachk:*grade-short*
      '(("ECONOMY" . "ECO") ("STANDARD" . "STD")
        ("ULTRA" . "ULTRA") ("THERMOLIGHT" . "THERMO")))

;; Entity types, by the job each does in the audit: what may be an
;; outline at all, which of those are closed by their nature rather
;; than by a flag, and what counts as loose (unbounded) output -- which
;; on the cover layer is also what a hinge is drawn as.
(setq spachk:*outline-types* '("LWPOLYLINE" "POLYLINE" "CIRCLE" "ELLIPSE"))
(setq spachk:*closed-types*  '("CIRCLE" "ELLIPSE"))
(setq spachk:*loose-types*   '("LINE" "ARC"))

;; Dimension subtypes whose span can be measured, by the low three bits
;; of DXF group 70: 0 = rotated, 1 = aligned.
(setq spachk:*linear-types*  '(0 1))

;; The word SPA labels a Velcro hinge with.  The arrangement audit
;; finds those labels by it, so it has to be the word SPA writes.
(setq spachk:*velcro-word*   "Velcro")

;; -- how the report is sized and placed --------------------------------

;; The report is scaled to the drawing, exactly as the check family's
;; siblings do it.  WIDE: on a wide, short sheet the reference height is
;; at least this fraction of the width.  LEAD: MTEXT line pitch as a
;; multiple of text height.  HMAX/HMIN: divisors clamping the height --
;; never taller than reference/HMAX, never shorter than reference/HMIN,
;; so a smaller number is a looser bound.  HFALL: the height used when
;; there is nothing to scale against.  GAP: space between drawing and
;; report, as a fraction of the drawing's width.
(setq spachk:*report-wide*  0.25)
(setq spachk:*report-lead*  1.66)
(setq spachk:*report-hmax*  30.0)
(setq spachk:*report-hmin*  200.0)
(setq spachk:*report-hfall* 2.5)   ; drawing units
(setq spachk:*report-gap*   0.05)

;; Gap between the main sheet and the DIMENSION AUDIT column beside it,
;; in text heights.
(setq spachk:*col-gap*      2.0)

;; The title is written this many times the base height, and a section
;; heading gets this much blank line above it.  Both are used twice:
;; once to draw, once to guess how many lines the sheet will run to --
;; HEAD is the allowance for the title, date, verdict and legend, and
;; HDG-LINES for a heading plus its gap.
(setq spachk:*title-scale*  1.5)
(setq spachk:*hdg-gap*      0.4)
(setq spachk:*head-lines*   4.5)
(setq spachk:*hdg-lines*    1.4)
(setq spachk:*dim-head*     2.5)   ; the same allowance for the audit column

;; Findings are indented under their heading by this string.
(setq spachk:*row-indent*   "  ")

;; -- the date the sheet must carry -------------------------------------

;; The sheet's date is written and read in this order, with this
;; separator: change both together, and remember the audit rewrites a
;; wrong date into this form.
(setq spachk:*date-sep*     "/")
(setq spachk:*date-order*   '(month day year))

;; -- numerical guards (rarely changed) ---------------------------------

;; A border edge shorter than this has no measurable size, and a
;; bounding box smaller than this has nothing to scale a report to.
(setq spachk:*tiny*         1.0e-6)   ; drawing units

;; How close a foam sheet's dimension must come to the table's before
;; it counts as that sheet -- foam is cut to the inch, so this is
;; slack for a drawing's rounding, not a tolerance on the foam.
(setq spachk:*foam-slack*   0.01)     ; drawing units

;;; ----------------------------------------------------------------------
;;;  END TUNABLES.  What follows is STATE, not settings: what one run
;;;  has to remember while it runs.  The tutorial's
;;;  demo opens an undo group and switches the dimension style, but the
;;;  handler that must undo both lives in c:TUTORIALSPACHECK, a
;;;  different defun that cannot see spachk:demo's locals -- so both
;;;  bits of state are module globals, as is the sysvar snapshot.
(setq spachk:*sysold*      nil)      ; saved sysvars, restored on the way out
(setq spachk:*demo-ents*   nil)      ; what TUTORIALSPACHECK's demo drew
(setq spachk:*odstyle*     nil)      ; the dim style the demo switched off
;;; ======================================================================

;;; -------------------- small helpers -----------------------------------

(defun spachk:trim (s)
  (while (and (> (strlen s) 0) (= " " (substr s 1 1)))
    (setq s (substr s 2)))
  (while (and (> (strlen s) 0) (= " " (substr s (strlen s) 1)))
    (setq s (substr s 1 (1- (strlen s)))))
  s)

(defun spachk:join (lst sep / out s)
  (foreach s lst
    (setq out (if out (strcat out sep s) s)))
  (if out out ""))

;; A length as the report quotes it, in the drawing's own units
;; (LUNITS/LUPREC).  A plain (rtos v) follows DIMZIN in a feet-inch
;; drawing: at 0 (acad.dwt's), 2 or 8 a whole foot came out 5' and the
;; report MTEXT said a dimension "reads 5' but spans ..." -- the very
;; feet-with-no-inches spelling rule 6 flags, in SPACHECK's own report.
;; So LUNITS 3 and 4 are spelled by arithmetic; every other unit keeps
;; rtos, which is what the drafter reads on the sheet.
(defun spachk:dist (v)
  (if (member (getvar "LUNITS") '(3 4))
    (spachk:ftin v (getvar "LUNITS") (getvar "LUPREC"))
    (rtos v)))

;; CALOFIN-LIB.lsp's cal:ftin is this function; the copy is here because a standalone file has to load alone.
(defun spachk:ftin (v mode prec / neg den tot ft n in num g)
  (setq neg  (minusp v)
        prec (max 0 (min (if (= mode 3) 6 8) prec))
        den  (if (= mode 3) (expt 10 prec) (expt 2 prec))
        tot  (fix (+ (* (abs v) den) 0.5))
        ft   (/ tot (* 12 den))
        n    (- tot (* ft 12 den))
        in   (/ n den)
        num  (- n (* in den)))
  (strcat (if (and neg (> tot 0)) "-" "")
          (itoa ft) "'-" (itoa in)
          (cond ((= mode 3)
                 (if (> prec 0) (strcat "." (substr (itoa (+ den num)) 2)) ""))
                ((= num 0) "")
                (T (setq g (gcd num den))
                   (strcat " " (itoa (/ num g)) "/" (itoa (/ den g)))))
          "\""))

;; "MM/DD/YYYY HH:MM" off the computer clock, for the report's stamp --
;; the sheet's own MM/DD/YYYY, the form the Tech Title date is held to.
;; CDATE is decoded arithmetically, as spachk:today-mdy does: rtos of
;; it is trimmed by DIMZIN 8 (which SPA sets), so a sliced
;; (rtos CDATE 2 6) read "20260923.1" at ten o'clock and stamped " 1:".
;; Kept local rather than swapped for cal:datestr, whose YYYY-MM-DD is
;; the other review tools' form -- the one-file build printed that one
;; and the standalone this, for the same report.
(defun spachk:datestr ( / d tt)
  (setq d  (getvar "CDATE")
        tt (- d (fix d)))
  (strcat (spachk:mdy-str (spachk:today-mdy)) " "
          (spachk:pad2 (fix (+ (* tt 100) 1e-6))) ":"
          (spachk:pad2 (rem (fix (+ (* tt 10000) 1e-4)) 100))))

;; Everything after the last colon, trimmed: "Taper: 4-2" -> "4-2".
(defun spachk:aftercolon (s / i out)
  (setq i (strlen s) out s)
  (while (> i 0)
    (if (= ":" (substr s i 1))
        (progn (setq out (substr s (1+ i))) (setq i 0))
        (setq i (1- i))))
  (spachk:trim out))

;; Does s contain sub?  Case-sensitive, plain AutoLISP.
(defun spachk:has (s sub / n m i found)
  ;; nil-safe: an absent label or text override is simply "no match"
  (if (or (null s) (null sub)) (setq s "" sub "x"))
  (setq n (strlen s) m (strlen sub) i 1 found nil)
  (if (> m 0)
      (while (and (not found) (<= i (- n m -1)))
        (if (= sub (substr s i m)) (setq found t))
        (setq i (1+ i))))
  found)

;;; -------------------- report text -------------------------------------
;;;  A report row is (text . level): level nil = all clear, 1 = a
;;;  problem, 2 = advice, 3 = a section heading.  The four render
;;;  differently in the MTEXT.

;; A report row is (text . level): nil = all clear, 1 = a problem,
;; 2 = advice, 3 = a section heading.  spachk:lvl-p compares
;; nil-safely -- (= nil 1) is not something to rely on.
(defun spachk:row (s lvl) (cons s lvl))
(defun spachk:row-txt (r) (car r))
(defun spachk:row-lvl (r) (cdr r))
(defun spachk:lvl-p (r n) (and (spachk:row-lvl r) (= (spachk:row-lvl r) n)))

(defun spachk:red (s)
  (strcat "{\\C" (itoa spachk:*flag-color*) ";" s "}"))

(defun spachk:cyan (s)
  (strcat "{\\C" (itoa spachk:*advice-color*) ";" s "}"))

(defun spachk:small (s)
  (strcat "{\\H" (rtos spachk:*green-scale* 2 2) "x;" s "}"))

;; The report's title line, at *title-scale* times the base height.
(defun spachk:big (s)
  (strcat "{\\H" (rtos spachk:*title-scale* 2 2) "x;" s "}"))

;; A section heading: underlined, with a thin blank line above it so
;; the sections read as blocks.  The braces scope both codes, and the
;; \P inside the first group is a paragraph break at *hdg-gap* of the
;; height -- a narrow gap, not a full empty line.
(defun spachk:hdg (s)
  (strcat "{\\H" (rtos spachk:*hdg-gap* 2 2) "x;\\P}{\\L" s "}"))

;; Findings are indented two spaces under their heading; the indent
;; sits INSIDE the colour/height wrap so a problem row still starts
;; with its colour code.
(defun spachk:render (r)
  (cond ((spachk:lvl-p r 3) (spachk:hdg (spachk:row-txt r)))
        ((spachk:lvl-p r 1) (spachk:red (strcat "  " (spachk:row-txt r))))
        ((spachk:lvl-p r 2) (spachk:cyan (strcat "  " (spachk:row-txt r))))
        (t (spachk:small (strcat "  " (spachk:row-txt r))))))

;; MTEXT carries at most 250 characters in group 1; anything longer goes
;; out as leading group 3 chunks with the tail in group 1.  A report is
;; always longer than that, so skipping the split loses everything past
;; the first 250 characters.
(defun spachk:mtext (ins height width text layer / dxf)
  (setq dxf (list '(0 . "MTEXT")
                  '(100 . "AcDbEntity")
                  (cons 8 layer)
                  '(100 . "AcDbMText")
                  (cons 10 ins)
                  (cons 40 height)
                  (cons 41 width)
                  '(71 . 1)
                  '(72 . 5)))
  (while (> (strlen text) 250)
    (setq dxf  (append dxf (list (cons 3 (substr text 1 250))))
          text (substr text 251)))
  (entmakex (append dxf (list (cons 1 text)))))

;;; -------------------- layers ------------------------------------------
;;;  The canonical ensure-layer: create, or when it already exists make
;;;  sure it is on, thawed and unlocked -- without this a successful run
;;;  onto a frozen layer looks like the command did nothing.

(defun spachk:ensure-layer (name color / rec ed flags col fixed)
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
      (if (/= 0 (logand 5 flags))
        (setq ed    (subst (cons 70 (- flags (logand 5 flags)))
                           (assoc 70 ed) ed)
              fixed T))
      (if (< col 0)
        (setq ed    (subst (cons 62 (abs col)) (assoc 62 ed) ed)
              fixed T))
      (if fixed
        (progn
          (entmod ed)
          (princ (strcat "\nSPACHECK: layer " name
                         " was off, frozen or locked - restored so the"
                         " result is visible.")))))))

;;; -------------------- entity helpers ----------------------------------

(defun spachk:dxf (code ent) (cdr (assoc code (entget ent))))

(defun spachk:etype (ent) (spachk:dxf 0 ent))

(defun spachk:layer (ent) (spachk:dxf 8 ent))

(defun spachk:on-layer-p (ent name)
  (= (strcase (spachk:layer ent)) (strcase name)))

(defun spachk:bbox (ent / obj ll ur)
  (if (and (setq obj (vlax-ename->vla-object ent))
           (progn (vla-getboundingbox obj 'll 'ur) t))
    (list (vlax-safearray->list ll) (vlax-safearray->list ur))))

;; Overall extents of a list of entities: ((minx miny) (maxx maxy)).
(defun spachk:bbox-of (ents / e bb lo hi)
  (foreach e ents
    (if (setq bb (spachk:bbox e))
      (setq lo (if lo (list (min (car lo) (caar bb))
                            (min (cadr lo) (cadar bb)))
                   (list (caar bb) (cadar bb)))
            hi (if hi (list (max (car hi) (caadr bb))
                            (max (cadr hi) (cadadr bb)))
                   (list (caadr bb) (cadadr bb))))))
  (if (and lo hi) (list lo hi)))

(defun spachk:bw (bb) (- (car (cadr bb)) (car (car bb))))
(defun spachk:bh (bb) (- (cadr (cadr bb)) (cadr (car bb))))

;; Is inner's bounding box wholly inside outer's, with slack?
(defun spachk:inside-p (inner outer slack)
  (and (>= (- (caar inner) (caar outer)) (- slack))
       (>= (- (cadar inner) (cadar outer)) (- slack))
       (>= (- (caadr outer) (caadr inner)) (- slack))
       (>= (- (cadadr outer) (cadadr inner)) (- slack))))

;; Do two boxes overlap or touch, with slack?
(defun spachk:touch-p (a b slack)
  (and (<= (caar a) (+ (caadr b) slack)) (<= (caar b) (+ (caadr a) slack))
       (<= (cadar a) (+ (cadadr b) slack)) (<= (cadar b) (+ (cadadr a) slack))))

(defun spachk:bbunion (a b)
  (list (list (min (caar a) (caar b)) (min (cadar a) (cadar b)))
        (list (max (caadr a) (caadr b)) (max (cadadr a) (cadadr b)))))

;; Boxes that come within slack of each other merged into one, until
;; no two left do: one sheet's frame -- a polyline, four lines, a double
;; rule -- comes out as one box, and each separate sheet as a box of its
;; own.  The slack is what tells a sheet from a gap: a hand-drawn frame's
;; corners are open by a thousandth or half a unit, sheets sit hundreds
;; apart, and joining only boxes that met to 1e-4 split one correct
;; four-line frame into four "borders" and measured a single line.
(defun spachk:clusters (bbs slack / out hit rest merged bb c)
  (setq merged T)
  (while merged
    (setq merged nil out nil)
    (foreach bb bbs
      (setq hit bb rest nil)
      (foreach c out
        (if (spachk:touch-p c hit slack)
          (setq hit (spachk:bbunion c hit) merged T)
          (setq rest (cons c rest))))
      (setq out (cons hit rest)))
    (setq bbs out))
  bbs)

;; How far a point is from a box: 0 inside it.
(defun spachk:box-dist (p bb / dx dy)
  (setq dx (max 0.0 (- (caar bb) (car p)) (- (car p) (caadr bb)))
        dy (max 0.0 (- (cadar bb) (cadr p)) (- (cadr p) (cadadr bb))))
  (sqrt (+ (* dx dx) (* dy dy))))

;; The middle of the spa being checked -- its cover outline, or failing
;; that the whole selection -- which is what "nearest the spa" means
;; when a drawing holds more than one sheet.  nil with nothing to measure.
(defun spachk:focus (ss / bb ents i)
  (setq bb (spachk:bbox-of (spachk:outline-ents ss spachk:*lay-cover*)))
  (if (and (null bb) ss)
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq ents (cons (ssname ss i) ents) i (1+ i)))
      (setq bb (spachk:bbox-of ents))))
  (if bb
    (list (* 0.5 (+ (caar bb) (caadr bb)))
          (* 0.5 (+ (cadar bb) (cadadr bb))))))

;; The space the drafter is working in, as group 410 names it.  CTAB
;; alone is wrong from inside a layout viewport: it names the layout
;; while every pick lands in model space.
(defun spachk:space ()
  (if (and (= 0 (getvar "TILEMODE")) (= 1 (getvar "CVPORT")))
    (getvar "CTAB")
    "Model"))

(defun spachk:closed-p (ent / f)
  (cond ((member (spachk:etype ent) spachk:*closed-types*) t)
        ((= (spachk:etype ent) "LWPOLYLINE")
         (setq f (spachk:dxf 70 ent))
         (and f (numberp f) (= 1 (logand 1 f))))
        (t nil)))

;; A bounded outline: one closed entity of a type SPA emits.
(defun spachk:outline-ents (ss layer / i e out)
  (setq i 0)
  (if ss
    (repeat (sslength ss)
      (setq e (ssname ss i) i (1+ i))
      (if (and (entget e)
               (spachk:on-layer-p e layer)
               (member (spachk:etype e) spachk:*outline-types*))
        (setq out (cons e out)))))
  (reverse out))

;; The loose lines and arcs on a layer -- on COVER these are the hinges;
;; on POOL they are the pre-bounded output that should be a polyline.
(defun spachk:loose-ents (ss layer / i e out)
  (setq i 0)
  (if ss
    (repeat (sslength ss)
      (setq e (ssname ss i) i (1+ i))
      (if (and (entget e)
               (spachk:on-layer-p e layer)
               (member (spachk:etype e) spachk:*loose-types*))
        (setq out (cons e out)))))
  (reverse out))

(defun spachk:ents-of-type (ss etype / i e out)
  (setq i 0)
  (if ss
    (repeat (sslength ss)
      (setq e (ssname ss i) i (1+ i))
      (if (and (entget e) (= (spachk:etype e) etype))
        (setq out (cons e out)))))
  (reverse out))

;;; -------------------- blocks ------------------------------------------

;; Attributes of a block reference, as (("TAG" . value) ...).
(defun spachk:attribs (ename / e ed out)
  (setq e (entnext ename))
  (while (and e (setq ed (entget e)) (= "ATTRIB" (cdr (assoc 0 ed))))
    (setq out (cons (cons (strcase (cdr (assoc 2 ed))) (cdr (assoc 1 ed))) out)
          e (entnext e)))
  (reverse out))

;; The Spa Cover Details block in the selection: the one whose name
;; matches, else any INSERT carrying a TAPER tag.
(defun spachk:find-details (ss / ins e best fallback nm)
  (setq ins (spachk:ents-of-type ss "INSERT"))
  (foreach e ins
    (setq nm (strcase (spachk:dxf 2 e)))
    (cond
      ((and (not best) (= nm (strcase spachk:*details-block*))) (setq best e))
      ((and (not fallback) (cdr (assoc "TAPER" (spachk:attribs e))))
       (setq fallback e))))
  (if best best fallback))

;; The first word of TABLE the upper-cased value contains, or nil.
;; Order matters: the table is walked top to bottom, first hit winning.
(defun spachk:vocab (v table / u hit p)
  (setq u (strcase (if v v "")))
  (foreach p table
    (if (and (not hit) (spachk:has u (strcase (car p))))
      (setq hit (cdr p))))
  hit)

(defun spachk:tapernorm (v)
  (spachk:vocab v spachk:*taper-words*))

(defun spachk:gradenorm (v / g)
  (setq g (spachk:vocab v spachk:*grade-words*))
  (if g g spachk:*grade-default*))

(defun spachk:gradeshort (g / p)
  (setq p (assoc g spachk:*grade-short*))
  (if p (cdr p) g))

;;; -------------------- dimensions --------------------------------------

(defun spachk:dim-style (ent / s)
  (setq s (spachk:dxf 3 ent))
  (if s s ""))

;; The measurement AutoCAD stores on the dimension (DXF 42).
(defun spachk:dim-meas (ent) (spachk:dxf 42 ent))

;; The text override, if any (DXF 1) -- SPA puts its note there.
(defun spachk:dim-text (ent / s)
  (setq s (spachk:dxf 1 ent))
  (if s s ""))

;; The two extension-line origins of a linear/aligned dimension.
(defun spachk:dim-pts (ent / ed)
  (setq ed (entget ent))
  (list (cdr (assoc 13 ed)) (cdr (assoc 14 ed))))

;; Is this a linear or aligned dimension (the kinds SPA places)?  A
;; dimension with no DXF 70 at all is not one we can classify, so it is
;; left out rather than guessed at -- reading nil into logand would take
;; the whole audit down over one malformed entity.
(defun spachk:linear-p (ent / f)
  (setq f (spachk:dxf 70 ent))
  (and f (numberp f) (member (logand 7 f) spachk:*linear-types*)))

;; The dimension line's own location (DXF 10).
(defun spachk:dim-loc (ent) (spachk:dxf 10 ent))

;; Every dimension in the selection, whatever layer it sits on.
(defun spachk:dims (ss) (spachk:ents-of-type ss "DIMENSION"))

;; The dimensions whose text carries a given note.
(defun spachk:dims-noted (dims note / e out)
  (foreach e dims
    (if (spachk:has (spachk:dim-text e) note) (setq out (cons e out))))
  (reverse out))

;; The hinges: the LINEs on the cover layer (the outline itself is a
;; polyline, a circle or an ellipse, so the two never confuse).
(defun spachk:hinge-lines (ss)
  (vl-remove-if-not '(lambda (e) (= (spachk:etype e) "LINE"))
                    (spachk:loose-ents ss spachk:*lay-cover*)))

;;; -------------------- the cover's own frame ----------------------------
;;;  SPA draws along the CURRENT UCS, so a spa drawn in a turned UCS has
;;;  a cover whose edges run at that UCS's angle in World.  Every size
;;;  and standoff the audit reads is one of SPA's -- "across", "up",
;;;  "2 ft above", "3 ft to the left" -- and those are the COVER'S axes.
;;;  Measured along World's instead, an 84 x 60 cover turned 30 degrees
;;;  is 102.7 x 94.0 and both its overalls "disagree" with it.  Nor may
;;;  the reviewer's UCS decide anything: one sheet has to get one verdict
;;;  whoever opens it, in whatever UCS.  So the frame is read off the
;;;  drawing, and off the drawing alone.
;;;
;;;  A FRAME is nil for World -- every helper then does exactly what it
;;;  did before there were frames -- or (cos sin) of the angle its X
;;;  axis makes in World.  A point's numbers in it are spachk:fr-pt's.
;;;
;;;  THE ANGLE, to a quarter turn.  The Cover Size overalls say it first
;;;  -- each measures along one of the cover's axes -- and failing them
;;;  the hinges, which run up it; the outline's straight edges then give
;;;  it exactly (the edge direction within 5 degrees of what they said,
;;;  so overalls drawn a hair off the outline cannot tilt the frame).
;;;  With neither, the outline's LONGEST straight edge decides.  Never
;;;  the heaviest edge direction: an octagon's or a cut corner's
;;;  diagonals can outweigh the square sides, and a 95 octagon with 40
;;;  faces measured 94.35 x 94.35 on its diagonals.
;;;
;;;  THE QUARTER that is up is NOT guessed from where the overalls
;;;  stand -- where they stand is exactly what the audit is there to
;;;  judge, and a pair with SPA's two standoffs swapped read as a spa
;;;  turned a quarter, with both failures gone.  It is taken from what
;;;  the drawing RECORDS: a DIMENSION keeps the UCS it was made in, as
;;;  group 51 (the negative of the angle from its OCS X axis to that
;;;  UCS's X axis), and dragging it does not change it; a dimension made
;;;  in World carries none (spachk:dim-turn).  The Cover Size overalls
;;;  vote; the other dimensions break a tie, or vote alone when there
;;;  are no overalls; a tie still standing goes to the turned UCS
;;;  (spachk:turn-vote).  Nothing to vote -- no dimension at all --
;;;  means World.  With hinges drawn the quarter must have them running
;;;  up it, as SPA's always do, and the turn chooses between the two
;;;  quarters that do; without, the quarter nearest the turn wins.  So
;;;  every drawing SPA made in World, whatever was dragged, erased or
;;;  swapped since, comes out World, and runs exactly the code it always
;;;  did.  The words "above" and "left" are the cover's own: what SPA
;;;  calls above in the UCS it drew in, whoever views the report and
;;;  however.

;; P, a World point or displacement, in frame FR -- P itself for World.
(defun spachk:fr-pt (fr p)
  (if fr
    (list (+ (* (car p) (car fr)) (* (cadr p) (cadr fr)))
          (- (* (cadr p) (car fr)) (* (car p) (cadr fr))))
    p))

;; An angle folded to the quarter turn nearest World's: (-45, 45] deg.
;; AutoLISP's rem keeps the dividend's sign, so a negative is lifted.
(defun spachk:fr-fold (a / q)
  (setq q (* 0.5 pi)
        a (rem a q))
  (if (< a 0.0) (setq a (+ a q)))
  (if (> a (* 0.5 q)) (setq a (- a q)))
  a)

;; How far apart two folded angles are, a quarter turn being no turn.
(defun spachk:fr-adiff (a b / d)
  (setq d (abs (- a b)))
  (if (> d (* 0.25 pi)) (- (* 0.5 pi) d) d))

;; PAIRS -- (angle . weight) -- gathered into directions a quarter turn
;; apart: ((folded-angle . total-weight) ...).
(defun spachk:fr-fams (pairs / p f fams fam hit out)
  (foreach p pairs
    (setq f (spachk:fr-fold (car p)) hit nil out nil)
    (foreach fam fams
      (if (and (not hit) (< (spachk:fr-adiff (car fam) f) 1.0e-6))
        (setq hit T
              out (cons (cons (car fam) (+ (cdr fam) (cdr p))) out))
        (setq out (cons fam out))))
    (setq fams (if hit out (cons (cons f (cdr p)) out))))
  fams)

;; The direction most of PAIRS run in, folded -- nil when there are none
;; or two directions weigh the same, which is no answer at all.  For
;; the overalls and the hinges, which all run along the cover's axes.
(defun spachk:fr-mode (pairs / fam best next)
  (foreach fam (spachk:fr-fams pairs)
    (cond ((or (null best) (> (cdr fam) (cdr best)))
           (setq next best best fam))
          ((or (null next) (> (cdr fam) (cdr next)))
           (setq next fam))))
  (if (and best (> (cdr best) 0.0)
           (or (null next)
               (> (- (cdr best) (cdr next)) (* 1.0e-6 (cdr best)))))
    (car best)))

;; The direction of the longest of PAIRS, folded -- nil when another
;; direction has one as long (a regular octagon), which says nothing.
(defun spachk:fr-long (pairs / p best f tie)
  (foreach p pairs
    (if (or (null best) (> (cdr p) (cdr best))) (setq best p)))
  (if best
    (progn
      (setq f (spachk:fr-fold (car best)))
      (foreach p pairs
        (if (and (>= (cdr p) (* (- 1.0 1.0e-6) (cdr best)))
                 (>= (spachk:fr-adiff (spachk:fr-fold (car p)) f) 1.0e-6))
          (setq tie T)))
      (if (not tie) f))))

;; Angle A made exact: the direction in FAMS within 5 degrees of it, or
;; A itself when none is.
(defun spachk:fr-snap (a fams / fam d bd best)
  (foreach fam fams
    (setq d (spachk:fr-adiff (car fam) a))
    (if (or (null bd) (< d bd)) (setq bd d best (car fam))))
  (if (and best (<= bd (/ pi 36.0))) best a))

;; P -- a LWPOLYLINE's, CIRCLE's or ARC's group 10, an old POLYLINE's
;; vertex -- is in ENT's OBJECT coordinates.  An entity in the World
;; plan (no 210, or 0,0,1) is its own OCS; any other goes through its
;; 210 -- a mirrored one, 0,0,-1, runs X backwards.  In World, 2D.
(defun spachk:ocs-pt (p ent / n w)
  (setq n (spachk:dxf 210 ent))
  (if (or (null n) (equal n '(0.0 0.0 1.0) 1.0e-12))
    (list (car p) (cadr p))
    (progn
      (setq w (trans (list (car p) (cadr p) (if (caddr p) (caddr p) 0.0))
                     ent 0))
      (list (car w) (cadr w)))))

;; -1.0 when ENT's OCS runs the other way round from World's (its 210
;; points down), so a bulge or an arc's sweep reads backwards; else 1.0.
(defun spachk:ocs-sense (ent / n)
  (setq n (spachk:dxf 210 ent))
  (if (and n (< (caddr n) 0.0)) -1.0 1.0))

;; A polyline's segments, in World, each as (p q bulge) with p and q 2D;
;; the closing one included when the polyline is closed.  Reads both
;; the LWPOLYLINE SPA draws and an old-style POLYLINE's VERTEX chain,
;; leaving out a spline's frame points (vertex flag 16), which the
;; curve does not pass through.
(defun spachk:pl-segs (ent / ed ty sn z p vs e v f n i a b out)
  (setq ed (entget ent)
        ty (cdr (assoc 0 ed))
        sn (spachk:ocs-sense ent))
  (cond
    ((= ty "LWPOLYLINE")
     (setq z (if (numberp (cdr (assoc 38 ed))) (cdr (assoc 38 ed)) 0.0))
     (foreach p ed
       (cond ((= (car p) 10)
              (setq vs (cons (list (spachk:ocs-pt (list (cadr p) (caddr p) z)
                                                  ent)
                                   0.0)
                             vs)))
             ((and (= (car p) 42) vs)
              (setq vs (cons (list (caar vs) (* sn (cdr p))) (cdr vs)))))))
    ((= ty "POLYLINE")
     (setq e (entnext ent))
     (while (and e (= (spachk:etype e) "VERTEX"))
       (setq v (entget e)
             f (if (numberp (cdr (assoc 70 v))) (cdr (assoc 70 v)) 0))
       (if (/= 16 (logand 16 f))
         (setq vs (cons (list (spachk:ocs-pt (cdr (assoc 10 v)) ent)
                              (* sn (if (assoc 42 v) (cdr (assoc 42 v)) 0.0)))
                        vs)))
       (setq e (entnext e)))))
  (setq vs (reverse vs) n (length vs) i 0)
  (repeat (if (= 1 (logand 1 (if (numberp (cdr (assoc 70 ed)))
                                 (cdr (assoc 70 ed)) 0)))
              n
              (max 0 (1- n)))
    (setq a   (nth i vs)
          b   (nth (rem (1+ i) n) vs)
          out (cons (list (car a) (car b) (cadr a)) out)
          i   (1+ i)))
  (reverse out))

;; The quadrant points of the arc a bulged segment P->Q sweeps (P and Q
;; already in the frame): a radius corner reaches as far as its arc,
;; not its chord.  nil for a straight segment.
(defun spachk:arc-quads (p q b / l h mx my cx cy r a0 sw k a out)
  (setq l (distance p q))
  (if (and (> l 0.0) (> (abs b) 1.0e-12))
    (progn
      ;; the centre sits h along the left normal of P->Q from the
      ;; chord's middle; a positive bulge sweeps anticlockwise P to Q
      (setq h  (/ (* l (- 1.0 (* b b))) (* 4.0 b))
            mx (* 0.5 (+ (car p) (car q)))
            my (* 0.5 (+ (cadr p) (cadr q)))
            cx (- mx (* h (/ (- (cadr q) (cadr p)) l)))
            cy (+ my (* h (/ (- (car q) (car p)) l)))
            r  (distance (list cx cy) p)
            sw (abs (* 4.0 (atan b)))
            a0 (if (> b 0.0)
                   (atan (- (cadr p) cy) (- (car p) cx))
                   (atan (- (cadr q) cy) (- (car q) cx)))
            k  0)
      (repeat 4
        (setq a (* k 0.5 pi))
        (if (<= (rem (+ (- a a0) (* 4.0 pi)) (* 2.0 pi)) sw)
          (setq out (cons (list (+ cx (* r (cos a))) (+ cy (* r (sin a))))
                          out)))
        (setq k (1+ k)))))
  out)

;; ENT's extents in frame FR, shaped as spachk:bbox's: ((lo) (hi)).
;; With FR nil it IS spachk:bbox -- the World box, as before.  Turned,
;; they are worked from the geometry: a polyline's vertices and its
;; arcs' quadrant points, a circle's centre and radius, an ellipse's two
;; axes (a whole one: an outline is closed), a line's ends, an arc's
;; ends and quadrant points; anything else falls back to the corners of
;; its World box, which holds it, if loosely.
(defun spachk:fr-box (ent fr / ty s p q c r a b ex ey a1 sw bb pts lo hi)
  (if (null fr)
    (spachk:bbox ent)
    (progn
      (setq ty (spachk:etype ent))
      (cond
        ((member ty '("LWPOLYLINE" "POLYLINE"))
         (foreach s (spachk:pl-segs ent)
           (setq p   (spachk:fr-pt fr (car s))
                 q   (spachk:fr-pt fr (cadr s))
                 pts (cons p (append (spachk:arc-quads p q (caddr s))
                                     pts)))))
        ((= ty "CIRCLE")
         (setq c   (spachk:fr-pt fr (spachk:ocs-pt (spachk:dxf 10 ent) ent))
               r   (spachk:dxf 40 ent)
               pts (list (list (- (car c) r) (- (cadr c) r))
                         (list (+ (car c) r) (+ (cadr c) r)))))
        ((= ty "ELLIPSE")
         ;; an ellipse keeps its centre and major axis in World
         (setq c   (spachk:fr-pt fr (spachk:dxf 10 ent))
               a   (spachk:fr-pt fr (spachk:dxf 11 ent))
               r   (spachk:dxf 40 ent)
               b   (list (- (* r (cadr a))) (* r (car a)))
               ex  (sqrt (+ (* (car a) (car a)) (* (car b) (car b))))
               ey  (sqrt (+ (* (cadr a) (cadr a)) (* (cadr b) (cadr b))))
               pts (list (list (- (car c) ex) (- (cadr c) ey))
                         (list (+ (car c) ex) (+ (cadr c) ey)))))
        ((= ty "LINE")
         (setq pts (list (spachk:fr-pt fr (spachk:dxf 10 ent))
                         (spachk:fr-pt fr (spachk:dxf 11 ent)))))
        ((= ty "ARC")
         (setq c  (spachk:dxf 10 ent)
               r  (spachk:dxf 40 ent)
               a1 (spachk:dxf 50 ent)
               sw (rem (- (spachk:dxf 51 ent) a1) (* 2.0 pi)))
         (if (<= sw 0.0) (setq sw (+ sw (* 2.0 pi))))
         (setq p   (spachk:fr-pt fr (spachk:ocs-pt
                                      (list (+ (car c) (* r (cos a1)))
                                            (+ (cadr c) (* r (sin a1)))
                                            (if (caddr c) (caddr c) 0.0))
                                      ent))
               q   (spachk:fr-pt fr (spachk:ocs-pt
                                      (list (+ (car c) (* r (cos (+ a1 sw))))
                                            (+ (cadr c) (* r (sin (+ a1 sw))))
                                            (if (caddr c) (caddr c) 0.0))
                                      ent))
               pts (cons p (cons q (spachk:arc-quads
                                     p q (* (spachk:ocs-sense ent)
                                            (/ (sin (* 0.25 sw))
                                               (cos (* 0.25 sw)))))))))
        ((setq bb (spachk:bbox ent))
         (setq pts (list (spachk:fr-pt fr (car bb))
                         (spachk:fr-pt fr (cadr bb))
                         (spachk:fr-pt fr (list (caar bb) (cadadr bb)))
                         (spachk:fr-pt fr (list (caadr bb) (cadar bb)))))))
      (foreach p pts
        (setq lo (if lo (list (min (car lo) (car p)) (min (cadr lo) (cadr p)))
                        (list (car p) (cadr p)))
              hi (if hi (list (max (car hi) (car p)) (max (cadr hi) (cadr p)))
                        (list (car p) (cadr p)))))
      (if (and lo hi) (list lo hi)))))

;; The extents of every one of ENTS in frame FR, together.
(defun spachk:fr-box-of (ents fr / e bb out)
  (foreach e ents
    (if (setq bb (spachk:fr-box e fr))
      (setq out (if out (spachk:bbunion out bb) bb))))
  out)

;; Which way an outline's straight edges run, as (angle . length) --
;; an ellipse gives its major axis; a circle, or a polyline all arcs,
;; gives nothing.
(defun spachk:edge-dirs (ent / ty s p q a out)
  (setq ty (spachk:etype ent))
  (cond
    ((member ty '("LWPOLYLINE" "POLYLINE"))
     (foreach s (spachk:pl-segs ent)
       (setq p (car s) q (cadr s))
       (if (and (< (abs (caddr s)) 1.0e-9)
                (> (distance p q) spachk:*tiny*))
         (setq out (cons (cons (atan (- (cadr q) (cadr p))
                                     (- (car q) (car p)))
                               (distance p q))
                         out)))))
    ((= ty "ELLIPSE")
     (setq a (spachk:dxf 11 ent))
     (if (and a (> (+ (abs (car a)) (abs (cadr a))) spachk:*tiny*))
       (setq out (list (cons (atan (cadr a) (car a)) 1.0))))))
  out)

;; Which way one linear dimension measures, as a World angle: a rotated
;; dimension's own group 50, an aligned one's line through its points.
;; nil for any other kind.
(defun spachk:dim-dir (e / f p q)
  (setq f (spachk:dxf 70 e))
  (if (and f (numberp f))
    (cond
      ((= (logand 7 f) 0)
       (if (spachk:dxf 50 e) (spachk:dxf 50 e) 0.0))
      ((= (logand 7 f) 1)
       (setq p (spachk:dxf 13 e) q (spachk:dxf 14 e))
       (if (and p q
                (> (+ (abs (- (car q) (car p))) (abs (- (cadr q) (cadr p))))
                   spachk:*tiny*))
         (atan (- (cadr q) (cadr p)) (- (car q) (car p))))))))

;; Which way the linear overalls measure, as (angle . 1).
(defun spachk:dim-dirs (dims / e a out)
  (foreach e dims
    (if (setq a (spachk:dim-dir e))
      (setq out (cons (cons a 1.0) out))))
  out)

;; Which way LINEs run -- the hinges, a border's rules -- as
;; (angle . length).
(defun spachk:line-dirs (lines / e p q out)
  (foreach e lines
    (setq p (spachk:dxf 10 e) q (spachk:dxf 11 e))
    (if (and p q
             (> (distance (list (car p) (cadr p)) (list (car q) (cadr q)))
                spachk:*tiny*))
      (setq out (cons (cons (atan (- (cadr q) (cadr p)) (- (car q) (car p)))
                            (distance (list (car p) (cadr p))
                                      (list (car q) (cadr q))))
                      out))))
  out)

;; Where overall E stands against the cover box COVBB, both in frame FR:
;; ("above" . distance), ("left" . distance), or nil when it is on
;; neither side SPA uses.  Above is asked first: SPA's across dim is the
;; top one.
(defun spachk:standing (e covbb fr / loc dx dy)
  (if (setq loc (spachk:dim-loc e))
    (progn
      (setq loc (spachk:fr-pt fr loc)
            dy  (- (cadr loc) (cadadr covbb))    ; above the top
            dx  (- (caar covbb) (car loc)))      ; left of the left edge
      (cond ((> dy 0.0) (cons "above" dy))
            ((> dx 0.0) (cons "left" dx))))))

;; The turn of the UCS dimension E was made in, radians: the negative
;; of its group 51, or 0.0 -- World -- when it carries none.
(defun spachk:dim-turn (e / h)
  (setq h (spachk:dxf 51 e))
  (if (numberp h) (- h) 0.0))

;; Are two turns, each in [0, 2pi), the same one?
(defun spachk:turn-same (a b / d)
  (setq d (abs (- a b)))
  (or (< d 1.0e-6) (< (- (* 2.0 pi) d) 1.0e-6)))

;; DIMS' turns (spachk:dim-turn) tallied: ((turn . count) ...), each turn
;; in [0, 2pi).
(defun spachk:turn-tally (dims / e t0 votes v hit out)
  (foreach e dims
    (setq t0 (rem (spachk:dim-turn e) (* 2.0 pi)) hit nil out nil)
    (if (< t0 0.0) (setq t0 (+ t0 (* 2.0 pi))))
    (foreach v votes
      (if (and (not hit) (spachk:turn-same (car v) t0))
        (setq hit T out (cons (cons (car v) (1+ (cdr v))) out))
        (setq out (cons v out))))
    (setq votes (if hit out (cons (cons t0 1) out))))
  votes)

;; Of the turns CANDS, those TALLY gives the most votes (none: 0).
(defun spachk:turn-most (cands tally / c v n best out)
  (foreach c cands
    (setq n 0)
    (foreach v tally (if (spachk:turn-same (car v) c) (setq n (cdr v))))
    (cond ((or (null best) (> n best)) (setq best n out (list c)))
          ((= n best) (setq out (cons c out)))))
  out)

;; The UCS turn the drawing was made in, or nil with no dimension at
;; all.  The overalls COVN vote.  A tie among them goes to the turn the
;; OTHER dimensions -- Water's Edge, Overlap, corner marks, which SPA
;; made in the same UCS -- were made in most; a tie still standing to a
;; turned UCS over World (a dimension re-made by hand in World is the
;; edit, not the original), then to the turn nearest World.  With no
;; overalls the other dimensions vote alone, ties broken the same way.
(defun spachk:turn-vote (covn others / tally cands c turned d bd best)
  (setq tally (spachk:turn-tally others))
  (if covn
    (setq cands (spachk:turn-most
                  (mapcar 'car (spachk:turn-tally covn))
                  (spachk:turn-tally covn))
          cands (if (cdr cands) (spachk:turn-most cands tally) cands))
    (setq cands (spachk:turn-most (mapcar 'car tally) tally)))
  (foreach c cands
    (if (not (spachk:turn-same c 0.0)) (setq turned (cons c turned))))
  (if (and turned (cdr cands)) (setq cands turned))
  (foreach c cands
    (setq d (min c (- (* 2.0 pi) c)))
    (if (or (null bd) (< d bd)) (setq bd d best c)))
  best)

;; The cover's frame: nil for World, else (cos sin).  COV is the cover
;; outline (nil when there is not exactly one), COVN its overalls, DIMS
;; every dimension in the selection, HNGS the hinge lines.  See the
;; head of this section for the rule.
;;
;; The recorded turn is the UCS the dimensions were MADE in.  A drawing
;; ROTATEd after it was made keeps its dimensions' group 51 (whether
;; ROTATE rewrites it is unconfirmed), so the quarter is taken nearest a
;; turn it no longer has: right for a rotation under 45 degrees, a
;; quarter off past it -- no worse than reading everything in World.
(defun spachk:cover-frame (cov covn dims hngs / fams hint a tn k th d bd best
                                                cs up e p q most)
  (setq fams (if cov (spachk:fr-fams (spachk:edge-dirs cov)))
        hint (cond ((spachk:fr-mode (spachk:dim-dirs covn)))
                   ((spachk:fr-mode (spachk:line-dirs hngs))))
        a    (cond (hint (spachk:fr-snap hint fams))
                   ((if cov (spachk:fr-long (spachk:edge-dirs cov))))
                   (t 0.0))
        a    (spachk:fr-fold a)
        ;; the UCS the drawing was made in, else World
        tn   (cond ((spachk:turn-vote
                      covn (vl-remove-if '(lambda (e) (member e covn)) dims)))
                   (t 0.0))
        k    0)
  ;; the quarter turns of A the hinges run UP in -- SPA's hinges always
  ;; run up the cover, and the audit reads their runs along Y -- or all
  ;; four with no hinges; the recorded turn only chooses among those
  (repeat 4
    (setq th (+ a (* k 0.5 pi)) up 0)
    (foreach e hngs
      (setq p (spachk:fr-pt (list (cos th) (sin th)) (spachk:dxf 10 e))
            q (spachk:fr-pt (list (cos th) (sin th)) (spachk:dxf 11 e)))
      (if (> (abs (- (cadr q) (cadr p))) (abs (- (car q) (car p))))
        (setq up (1+ up))))
    (cond ((or (null most) (> up most)) (setq most up cs (list th)))
          ((= up most) (setq cs (cons th cs))))
    (setq k (1+ k)))
  ;; of those, the one nearest the recorded turn
  (foreach th (reverse cs)
    (setq d (rem (abs (- th tn)) (* 2.0 pi)))
    (if (> d pi) (setq d (- (* 2.0 pi) d)))
    (if (or (null bd) (< d bd)) (setq bd d best th)))
  ;; square to World is World: nil, and the code there always was
  (if (and (< (abs (sin best)) 1.0e-9) (> (cos best) 0.0))
    nil
    (list (cos best) (sin best))))

;; A border's own frame, from the entities of one sheet's frame: nil for
;; World (a border square to World measures as it always did), else the
;; direction of its longest straight edge, turned to the quarter in
;; which it is wider than tall -- a title block lies landscape.
(defun spachk:border-frame (ents / e pairs a c s k fr bb best)
  (foreach e ents
    (setq pairs (append (if (= (spachk:etype e) "LINE")
                            (spachk:line-dirs (list e))
                            (spachk:edge-dirs e))
                        pairs)))
  (setq a (spachk:fr-long pairs))
  (if (and a (> (abs a) 1.0e-9))
    (progn
      (setq c (cos a) s (sin a) k 0)
      (repeat 4
        (setq fr (nth k (list (list c s) (list (- s) c)
                              (list (- c) (- s)) (list s (- c))))
              bb (spachk:fr-box-of ents fr))
        (if (and (null best) bb
                 (>= (spachk:bw bb) (- (spachk:bh bb) spachk:*tiny*)))
          (setq best fr))
        (setq k (1+ k)))
      (if best best (list c s)))))

;;; -------------------- the hinge arrangement chart ----------------------
;;;  Copied from SPA (spa:hingetypes) so the audit measures against the
;;;  same rule the drawing was built to: fold hinges on even positions
;;;  and velcro on odd, across the whole row when pieces mod 4 is 0 or
;;;  2, and only to the chart's cutoff when it is odd, the rest
;;;  mirroring the left half.  Returns a list of "H" / "V", west to east.

(defun spachk:hingetypes (n allvel / hc m zone p out)
  (setq hc (1- n)
        m (rem n 4)
        zone (cond ((or (= m 0) (= m 2)) hc)
                   ((= m 1) (/ hc 2))
                   (t (/ (+ hc 2) 2)))
        p 0 out nil)
  (while (< p hc)
    (setq out (append out
                      (list (cond (allvel "V")
                                  ((< p zone) (if (= 0 (rem p 2)) "H" "V"))
                                  (t (nth (- hc 1 p) out)))))
          p (1+ p)))
  out)

(defun spachk:hallow (n allowed)
  (if (>= n 5) (member 5 allowed) (member n allowed)))

;; A rule against the longest hinge -> (needed . reason).  An OVER rule
;; with nothing to measure says so rather than guessing: the answer
;; depends entirely on a length, and inventing one would be worse than
;; admitting it is unknown.
(defun spachk:hardverdict (rule len / k v)
  (setq k (car rule) v (cadr rule))
  (cond
    ((eq k 'ALWAYS)  (cons t   "always for this grade"))
    ((eq k 'NEVER)   (cons nil "not used on this grade"))
    ((eq k 'REQUEST) (cons t   "upon request only"))
    ((not (and (numberp len) (numberp v)))
     (cons t "no hinge length to check - verify by hand"))
    ((> len v)       (cons t   (strcat "hinge " (rtos len 2 1)
                                       " over " (rtos v 2 0))))
    (t               (cons nil (strcat "hinge " (rtos len 2 1)
                                       " not over " (rtos v 2 0))))))

;;; -------------------- the title block ---------------------------------

;; A spa sheet's title block is exactly spachk:*title-frac* of the liner
;; block.  Returns the report sentence.
;; (sentence . T when the title block is right).  The FLAG is what
;; decides the finding: reading the sentence for the word "OK" made a
;; border layer with OK in its name pass a sheet that has no border.
(defun spachk:title-verdict (bb / bw bh tw th sw sh sc)
  (setq tw (* spachk:*title-frac* spachk:*liner-w*)
        th (* spachk:*title-frac* spachk:*liner-h*))
  (if (null bb)
    (cons (strcat "NO BORDER found on layer '" spachk:*border-layer* "'") nil)
    (progn
      (setq bw (spachk:bw bb) bh (spachk:bh bb))
      (if (or (<= bw spachk:*tiny*) (<= bh spachk:*tiny*))
        (cons "border has no measurable size" nil)
        (progn
          (setq sw (/ bw tw) sh (/ bh th) sc (min sw sh))
          (cond
            ;; out of proportion is wrong whatever its size
            ((> (abs (- sw sh)) (* spachk:*border-tol* (max sw sh)))
             (cons (strcat (spachk:dist bw) " x " (spachk:dist bh)
                     " - STRETCHED out of proportion (" (rtos sw 2 3)
                     "x wide but " (rtos sh 2 3) "x tall); a spa title"
                     " block is " (spachk:dist tw) " x " (spachk:dist th)) nil))
            ;; the size the user asked for by name
            ((and (> sc (- 1.0 spachk:*border-tol*))
                  (< sc (+ 1.0 spachk:*border-tol*)))
             (cons (strcat (spachk:dist bw) " x " (spachk:dist bh) " - "
                     (rtos spachk:*title-frac* 2 2)
                     "x the liner block, OK") t))
            (t
             (cons (strcat (spachk:dist bw) " x " (spachk:dist bh) " is "
                     (rtos (* sc spachk:*title-frac*) 2 3)
                     "x the liner block "
                     (spachk:dist spachk:*liner-w*) " x " (spachk:dist spachk:*liner-h*)
                     " - a spa title block must be exactly "
                     (rtos spachk:*title-frac* 2 2) "x it ("
                     (spachk:dist tw) " x " (spachk:dist th) ")") nil))))))))

;; Everything on the border layer, from the selection when it holds the
;; border and from the space the drafter is in when it does not.  A
;; drawing with more than one sheet has one frame per sheet, and all of
;; them measured together gave a verdict for a box no sheet has -- two
;; correct sheets side by side read STRETCHED.  So the frames are told
;; apart (spachk:clusters) and the one around, or nearest, the spa is
;; measured.  Returns (box . number-of-frames), nil with no border.
(defun spachk:border-box (ss / ents ss2 i e bb bbs cl f best bestd d mine fr)
  (setq ents nil i 0)
  (if ss
    (repeat (sslength ss)
      (setq e (ssname ss i) i (1+ i))
      (if (and (entget e) (spachk:on-layer-p e spachk:*border-layer*))
        (setq ents (cons e ents)))))
  (if (null ents)
    (progn
      (setq ss2 (ssget "_X" (list (cons 8 spachk:*border-layer*)
                                  (cons 410 (spachk:space))))
            i   0)
      (if ss2
        (repeat (sslength ss2)
          (setq e (ssname ss2 i) i (1+ i) ents (cons e ents))))))
  (foreach e ents
    (if (setq bb (spachk:bbox e)) (setq bbs (cons bb bbs))))
  ;; the slack: 2% of a spa sheet's width (8.4 units) -- far wider than
  ;; any corner a drafter leaves open, far narrower than the room
  ;; between two sheets
  (setq cl (spachk:clusters bbs (* 0.02 spachk:*title-frac*
                                   spachk:*liner-w*))
        f  (if (cdr cl) (spachk:focus ss)))
  (foreach bb cl
    (setq d (if f (spachk:box-dist f bb) 0.0))
    (if (or (null bestd) (< d bestd))
      (setq bestd d best bb)))
  ;; a nearest "frame" with no size of its own -- one stray line, or a
  ;; frame whose corners are open wider than the slack -- says nothing
  ;; about any sheet, and reporting it as the border read a correct
  ;; sheet as broken.  Everything on the layer is then measured
  ;; together, which is what a lone frame always was.
  (if (and (cdr cl)
           (or (<= (spachk:bw best) spachk:*tiny*)
               (<= (spachk:bh best) spachk:*tiny*)))
    (progn
      (setq best (car cl))
      (foreach bb (cdr cl) (setq best (spachk:bbunion best bb)))
      (setq cl (list best))))
  ;; the frame measured in its own axes: a sheet drawn in a turned UCS
  ;; is turned in World, and its World box read a correct 0.6x title
  ;; block as STRETCHED.  Square to World the frame is nil and the box
  ;; stands as found.
  (if best
    (progn
      (foreach e ents
        (if (and (setq bb (spachk:bbox e))
                 (spachk:inside-p bb best spachk:*tiny*))
          (setq mine (cons e mine))))
      (if (setq fr (spachk:border-frame mine))
        (setq best (spachk:fr-box-of mine fr)))))
  (if best (cons best (length cl))))

;;; ======================================================================
;;;  THE AUDIT
;;; ----------------------------------------------------------------------
;;;  One function per section.  Each takes what it needs and returns
;;;  ((row ...) . (flagged-entity ...)) -- the rows go into the report,
;;;  the entities are what SPACHECK offers to walk you through.
;;; ======================================================================

(defun spachk:res (rows ents) (cons rows ents))
(defun spachk:res-rows (r) (car r))
(defun spachk:res-ents (r) (cdr r))

;;; --- 1. the Spa Cover Details block ------------------------------------

(defun spachk:audit-block (ss / blk att g tp rows)
  (setq blk (spachk:find-details ss))
  (if (null blk)
    (spachk:res
      (list (spachk:row (strcat "Spa Cover Details: NO BLOCK named '"
                                spachk:*details-block*
                                "' in the selection - highlight it with the"
                                " drawing; the hinge checks need its taper")
                        1))
      nil)
    (progn
      (setq att (spachk:attribs blk)
            g   (cdr (assoc "GRADE" att))
            tp  (cdr (assoc "TAPER" att))
            g   (spachk:gradenorm (if g (spachk:aftercolon g) nil))
            tp  (if tp (spachk:tapernorm (spachk:aftercolon tp)) nil))
      (setq rows
            (list (spachk:row (strcat "Spa Cover Details: grade "
                                      (spachk:gradeshort g)
                                      ", taper " (if tp tp "NOT READABLE"))
                              (if tp nil 1))))
      (if (and tp (= g "THERMOLIGHT") (/= tp "1-3/8"))
        (setq rows (append rows
                    (list (spachk:row
                            (strcat "Spa Cover Details: THERMOLIGHT is"
                                    " always 1-3/8 flat, not " tp)
                            1)))))
      (spachk:res rows (if tp nil (list blk))))))

;;; --- 2/3. the outlines --------------------------------------------------

(defun spachk:audit-outline (ss layer what required
                             / outs loose rows ents e)
  (setq outs  (spachk:outline-ents ss layer)
        loose (spachk:loose-ents ss layer)
        rows nil ents nil)
  ;; hinges live on COVER as LINEs, so only ARCs count as loose there
  (if (= (strcase layer) (strcase spachk:*lay-cover*))
    (setq loose (vl-remove-if '(lambda (e) (= (spachk:etype e) "LINE")) loose)))
  (cond
    ((null outs)
     (if required
       (setq rows (list (spachk:row
                          (strcat what ": NO OUTLINE on layer " layer
                                  " - nothing to check against")
                          1)))
       (setq rows (list (spachk:row
                          (strcat what ": not drawn (one outline only)")
                          nil)))))
    ((> (length outs) 1)
     (setq rows (list (spachk:row
                        (strcat what ": " (itoa (length outs))
                                " outlines on layer " layer
                                " - there must be exactly one")
                        1))
           ents outs))
    (t
     (setq e (car outs))
     (if (spachk:closed-p e)
       (setq rows (list (spachk:row
                          (strcat what ": one closed "
                                  (spachk:etype e) ", OK")
                          nil)))
       (setq rows (list (spachk:row
                          (strcat what ": the " (spachk:etype e)
                                  " on " layer " is NOT CLOSED - the"
                                  " outline must be a bounded entity")
                          1))
             ents (list e)))))
  (if loose
    (setq rows (append rows
                (list (spachk:row
                        (strcat what ": " (itoa (length loose))
                                " loose line/arc"
                                (if (= 1 (length loose)) "" "s")
                                " on " layer
                                " - the outline should be one closed"
                                " polyline, not separate segments")
                        1)))
          ents (append ents loose)))
  (spachk:res rows ents))

;;; --- the two outlines together -----------------------------------------

(defun spachk:audit-nesting (covbb watbb / rows)
  (setq rows nil)
  (if (and covbb watbb)
    (if (spachk:inside-p watbb covbb spachk:*tiny*)
      (setq rows (list (spachk:row
                         (strcat "Cover vs water's edge: cover "
                                 (spachk:dist (spachk:bw covbb)) " x "
                                 (spachk:dist (spachk:bh covbb))
                                 " contains water's edge "
                                 (spachk:dist (spachk:bw watbb)) " x "
                                 (spachk:dist (spachk:bh watbb)) ", OK")
                         nil)))
      (setq rows (list (spachk:row
                         (strcat "Cover vs water's edge: the water's"
                                 " edge is NOT INSIDE the cover"
                                 " - the cover is always the larger"
                                 " of the two")
                         1)))))
  (spachk:res rows nil))

;;; --- 4. the dimensions --------------------------------------------------

;; Every dimension: right layer, right style, and does its measurement
;; agree with the distance between its own definition points?
(defun spachk:audit-dims (dims covdim watdim / rows ents e m d p1 p2 sty want)
  (setq rows nil ents nil)
  (foreach e dims
    ;; layer
    (if (not (spachk:on-layer-p e spachk:*lay-dim*))
      (setq rows (cons (spachk:row
                          (strcat "Dim " (spachk:dxf 5 e) ": on layer "
                                  (spachk:layer e) ", should be "
                                  spachk:*lay-dim*)
                          1)
                        rows)
            ents (cons e ents)))
    ;; style: a Water's Edge dim takes the 0.5 style, everything else
    ;; the cover style
    (setq want (if (spachk:has (spachk:dim-text e) spachk:*sfx-water*)
                   spachk:*ds-water* spachk:*ds-cover*)
          sty  (spachk:dim-style e))
    (if (and (/= sty "") (/= (strcase sty) (strcase want)))
      (setq rows (cons (spachk:row
                          (strcat "Dim " (spachk:dxf 5 e) ": style '"
                                  sty "', should be '" want "'")
                          1)
                        rows)
            ents (cons e ents)))
    ;; does it measure what it spans?
    (if (spachk:linear-p e)
      (progn
        (setq p1 (car (spachk:dim-pts e))
              p2 (cadr (spachk:dim-pts e))
              m  (spachk:dim-meas e))
        (if (and p1 p2 m)
          (progn
            (setq d (distance p1 p2))
            (if (> (abs (- d m)) spachk:*meas-tol*)
              (setq rows (cons (spachk:row
                                  (strcat "Dim " (spachk:dxf 5 e)
                                          ": reads " (spachk:dist m)
                                          " but spans " (spachk:dist d)
                                          " - the dimension DISAGREES"
                                          " with its own points")
                                  1)
                                rows)
                    ents (cons e ents))))))))
  (spachk:res (reverse rows) (reverse ents)))

;; Every dimension belongs on spachk:*lay-dim*.  The per-dimension
;; audit says so one dimension at a time, in the report's DIMENSION
;; AUDIT column; this is the roster-wide verdict, and it carries the
;; suggestion to run CDIM over the strays.  It is the one dimension
;; check LITESPACHECKSCAN keeps -- it costs a layer read apiece, and a
;; sheet whose dimensions sit on the wrong layer plots wrong however
;; sound the dimensions themselves are.  The offending layers are
;; named, since that is what you need to go fix them.
(defun spachk:audit-dimlayer (dims / n off lays lay e s)
  (setq n 0 off 0 lays nil)
  (foreach e dims
    (if (entget e)
      (progn
        (setq n   (1+ n)
              lay (spachk:layer e))
        (if (/= (strcase lay) (strcase spachk:*lay-dim*))
          (progn
            (setq off (1+ off))
            (if (not (member (strcase lay) lays))
              (setq lays (cons (strcase lay) lays))))))))
  (cond
    ((= n 0)
     (spachk:res (list (spachk:row (strcat "Dimension layer: no dimensions"
                                           " in the selection")
                                   1))
                 nil))
    ((= off 0)
     (spachk:res (list (spachk:row (strcat "Dimension layer: all " (itoa n)
                                           " on " spachk:*lay-dim*)
                                   nil))
                 nil))
    (t
     (spachk:res (list (spachk:row
                         (strcat "Dimension layer: " (itoa off) " of "
                                 (itoa n) " NOT on layer "
                                 spachk:*lay-dim* " ("
                                 (spachk:join (reverse lays) ", ")
                                 ") - run " spachk:*dimfix-cmd*
                                 " to move them")
                         1))
                 nil))))

;; The roster: are the dimensions a finished spa sheet needs present,
;; and do the overalls read the outline's true size?
;; FR is the cover's frame (spachk:cover-frame), which COVBB and WATBB
;; are measured in.
(defun spachk:audit-roster (dims cov wat covbb watbb fr / rows ents covn
                                           watn lapn m want e a d)
  (setq rows nil ents nil
        covn (spachk:dims-noted dims spachk:*sfx-cover*)
        watn (spachk:dims-noted dims spachk:*sfx-water*)
        lapn (spachk:dims-noted dims spachk:*sfx-lap*))
  ;; --- the cover's overalls
  (cond
    ((null covn)
     (setq rows (append rows
                 (list (spachk:row
                         (strcat "Overalls: NO dimension carries the '"
                                 spachk:*sfx-cover* "' note")
                         1)))))
    (t
     (setq rows (append rows
                 (list (spachk:row
                         (strcat "Overalls: " (itoa (length covn))
                                 " dimension"
                                 (if (= 1 (length covn)) "" "s")
                                 " noted '" spachk:*sfx-cover* "'")
                         nil))))
     ;; each must read one of the cover's two extents
     (if covbb
       (foreach e covn
         (setq m (spachk:dim-meas e))
         (if m
           (if (and (> (abs (- m (spachk:bw covbb))) spachk:*meas-tol*)
                    (> (abs (- m (spachk:bh covbb))) spachk:*meas-tol*))
             (setq rows (append rows
                         (list (spachk:row
                                 (strcat "Overall " (spachk:dxf 5 e)
                                         ": reads " (spachk:dist m)
                                         " but the cover measures "
                                         (spachk:dist (spachk:bw covbb)) " x "
                                         (spachk:dist (spachk:bh covbb)))
                                 1)))
                   ents (cons e ents))))))))
  ;; --- the water's edge overalls, when there is a water's edge
  (if wat
    (if (null watn)
      (setq rows (append rows
                  (list (spachk:row
                          (strcat "Water's edge: drawn, but NO dimension"
                                  " carries the '" spachk:*sfx-water*
                                  "' note")
                          1))))
      (setq rows (append rows
                  (list (spachk:row
                          (strcat "Water's edge: " (itoa (length watn))
                                  " dimension"
                                  (if (= 1 (length watn)) "" "s")
                                  " noted '" spachk:*sfx-water* "'")
                          nil))))))
  ;; --- the overlap dimension, required only when both are drawn
  (if (and cov wat)
    (if (null lapn)
      (setq rows (append rows
                  (list (spachk:row
                          (strcat "Overlap: both outlines are drawn but"
                                  " there is NO '" spachk:*sfx-lap*
                                  "' dimension")
                          1))))
      (progn
        ;; the lap along the way the dimension MEASURES, in the cover's
        ;; frame: SPA dimensions the lap at the bottom, up the cover, so
        ;; a water's edge lapped 3 across and 2 up reads 2 -- and read
        ;; against the across lap, SPA's own drawing failed
        (setq m    (spachk:dim-meas (car lapn))
              a    (spachk:dim-dir (car lapn))
              d    (if a (spachk:fr-pt fr (list (cos a) (sin a))))
              want (if (and covbb watbb)
                       (if (and d (> (abs (cadr d)) (abs (car d))))
                           (* 0.5 (- (spachk:bh covbb)
                                     (spachk:bh watbb)))
                           (* 0.5 (- (spachk:bw covbb)
                                     (spachk:bw watbb))))
                       nil))
        (if (and m want (> (abs (- m want)) spachk:*meas-tol*))
          (setq rows (append rows
                      (list (spachk:row
                              (strcat "Overlap: reads " (spachk:dist m)
                                      " but the cover laps the water's"
                                      " edge by " (spachk:dist want))
                              1)))
                ents (cons (car lapn) ents))
          (setq rows (append rows
                      (list (spachk:row
                              (strcat "Overlap: " (spachk:dist m) ", OK")
                              nil))))))))
  (spachk:res rows (reverse ents)))

;; The overalls' standoffs -- SPA puts the across dim 2 ft above the
;; cover and the up dim 3 ft to its left.  Above and left are the
;; cover's own (spachk:cover-frame): this form measures along World's,
;; and is what the audit ran before there were frames.
(defun spachk:audit-standoff (covn covbb)
  (spachk:audit-standoff-in covn covbb nil))

;; The same in frame FR, which COVBB is already measured in.  Above and
;; left are the cover's own -- SPA's, in the UCS it drew in.
(defun spachk:audit-standoff-in (covn covbb fr / rows e st)
  (setq rows nil)
  (if (and covbb covn)
    (foreach e covn
      (setq st (spachk:standing e covbb fr))
      (cond
        ;; above the cover: the across dim
        ((and st (= (car st) "above"))
         (if (> (abs (- (cdr st) spachk:*topoff*)) spachk:*off-tol*)
           (setq rows (append rows
                       (list (spachk:row
                               (strcat "Overall " (spachk:dxf 5 e)
                                       ": stands " (spachk:dist (cdr st))
                                       " above the cover, SPA puts it "
                                       (spachk:dist spachk:*topoff*))
                               1))))))
        ;; left of the cover: the up dim
        ((and st (= (car st) "left"))
         (if (> (abs (- (cdr st) spachk:*dimoff*)) spachk:*off-tol*)
           (setq rows (append rows
                       (list (spachk:row
                               (strcat "Overall " (spachk:dxf 5 e)
                                       ": stands " (spachk:dist (cdr st))
                                       " left of the cover, SPA puts it "
                                       (spachk:dist spachk:*dimoff*))
                               1)))))))))
  (spachk:res rows nil))

;;; --- 5. the hinges ------------------------------------------------------

;; A hinge's label: the MTEXT on the TEXT layer nearest its line.
(defun spachk:hinge-label (hng labels / best bestd p q d e bb)
  (setq bb (spachk:bbox hng))
  (if bb
    (progn
      (setq p (list (* 0.5 (+ (caar bb) (caadr bb)))
                    (* 0.5 (+ (cadar bb) (cadadr bb)))))
      (foreach e labels
        (setq q (spachk:dxf 10 e)
              d (distance (list (car p) (cadr p)) (list (car q) (cadr q))))
        (if (or (null bestd) (< d bestd)) (setq bestd d best e)))))
  (if best (spachk:dxf 1 best)))

;; WHICH SHEET THE COVER WAS LAID OUT TO.  A taper row can carry more
;; than one foam sheet -- STANDARD 3-2 and 4-2 each carry two -- and
;; SPA does not use the first: spa:hbest solves and SCORES every sheet
;; in the row and keeps the winner, then says which one it took
;; ("FOAM SHEET USED: 49.50 x 102").  Reading (car opts) here measured
;; SPA's own drawing against a sheet SPA had explicitly rejected, and
;; red-flagged it: a 98 x 60 cover on STANDARD 3-2 goes to the 49.5
;; sheet because 48 would need 3 pieces and that row allows only 2,
;; and the audit then called the 49 piece an overrun of "the 48.0000
;; sheet".  The same (car opts) fixed the length check to the wrong
;; sheet, which can miss a real overrun as easily as invent one.
;;
;; So the sheet is chosen from what was DRAWN, and chosen the way that
;; is safe to be wrong: the one the geometry fits.  If none fits, the
;; drawing overruns every sheet the row offers, and the complaint is
;; made against the most generous one -- the widest, then the longest
;; -- so a reported overrun is one no sheet in the row could have
;; absorbed.  WIDE / RUN are nil when there is nothing to measure
;; (no cover outline, no hinges), and then that half does not
;; discriminate.
(defun spachk:foampick (opts wide run / best fits opt w l)
  (foreach opt opts
    (setq w (car opt) l (cdr opt))
    (if (and (or (null wide) (<= wide (+ w spachk:*foam-slack*)))
             (or (null run) (null l) (<= run (+ l spachk:*foam-slack*)))
             (null fits))
        (setq fits opt)))
  (if fits
      fits
      (progn                      ; nothing fits: the most generous one
        (foreach opt opts
          (if (or (null best)
                  (> (car opt) (car best))
                  (and (= (car opt) (car best))
                       (> (if (cdr opt) (cdr opt) 0.0)
                          (if (cdr best) (cdr best) 0.0))))
              (setq best opt)))
        best)))

;; HNGS are the hinge lines (spachk:hinge-lines), found once by the
;; audit.  FR is the cover's frame (spachk:cover-frame), which COVBB is
;; measured in: a hinge runs along its Y and the pieces lie along its X.
(defun spachk:audit-hinges (ss hngs covbb grade taper fr / rows ents labels
                                                 n xs row opts allowed fw fl
                                                 sorted e want got
                                                 maxrun maxpiece prev
                                                 allvel hw h r k nm vd lvl)
  (setq rows nil ents nil
        labels (vl-remove-if-not
                 '(lambda (e) (spachk:on-layer-p e spachk:*lay-text*))
                 (spachk:ents-of-type ss "MTEXT")))
  (if (null hngs)
    (spachk:res
      (list (spachk:row "Hinges: none drawn on layer COVER" 1)) nil)
    (progn
      ;; west to east, along the cover
      (setq sorted (vl-sort hngs
                     '(lambda (a b)
                        (< (car (spachk:fr-pt fr (spachk:dxf 10 a)))
                           (car (spachk:fr-pt fr (spachk:dxf 10 b)))))))
      (setq n (1+ (length sorted))
            allvel (= grade "THERMOLIGHT"))
      ;; --- the piece count against the taper
      (setq row nil)
      (foreach r spachk:*foamtab*
        (if (and (not row) (= (car r) grade) (= (cadr r) taper))
          (setq row r)))
      (if (not row)
        (foreach r spachk:*foamtab*
          (if (and (not row) (= (car r) "STANDARD") (= (cadr r) taper))
            (setq row r))))
      (if row
        (setq opts (caddr row) allowed (cadddr row))
        (setq opts (list (cons 48.0 96.0)) allowed (list 2 3 4 5)))
      (setq rows (append rows
                  (list (spachk:row
                          (strcat "Hinges: " (itoa (length sorted))
                                  " drawn, so " (itoa n) " pieces ("
                                  (spachk:gradeshort grade) " " taper ")")
                          nil))))
      (if (not (spachk:hallow n allowed))
        (setq rows (append rows
                    (list (spachk:row
                            (strcat "Pieces: " (itoa n)
                                    " is NOT an acceptable count for "
                                    (spachk:gradeshort grade) " " taper)
                            1)))))
      ;; --- hinge runs against the foam length.  A hinge's run is its
      ;;     own length, so this stands whether or not the cover outline
      ;;     is there to be measured -- and it must, because the
      ;;     hardware advice below reads maxrun and a nil would take the
      ;;     whole audit down over the one drawing most in need of it.
      (setq maxrun 0.0)
      (foreach e sorted
        (setq maxrun (max maxrun
                          (abs (- (cadr (spachk:fr-pt fr (spachk:dxf 11 e)))
                                  (cadr (spachk:fr-pt fr (spachk:dxf 10 e))))))))
      ;; the widest piece, measured before either check so the sheet can
      ;; be chosen from the drawing rather than from the row's order
      (if covbb
          (progn
            (setq maxpiece 0.0 prev (caar covbb))
            (foreach e sorted
              (setq maxpiece (max maxpiece
                                  (- (car (spachk:fr-pt fr (spachk:dxf 10 e)))
                                     prev))
                    prev (car (spachk:fr-pt fr (spachk:dxf 10 e)))))
            (setq maxpiece (max maxpiece (- (caadr covbb) prev)))))
      (setq row (spachk:foampick opts maxpiece maxrun)
            fw  (car row)
            fl  (cdr row))
      (if (and fl (> maxrun (+ fl spachk:*foam-slack*)))
        (setq rows (append rows
                    (list (spachk:row
                            (strcat "Foam length: longest hinge "
                                    (spachk:dist maxrun) " exceeds the "
                                    (spachk:dist fl) " sheet")
                            1))))
        (setq rows (append rows
                    (list (spachk:row
                            (strcat "Foam length: longest hinge "
                                    (spachk:dist maxrun)
                                    (if fl
                                        (strcat " within " (spachk:dist fl) ", OK")
                                        (strcat " - THERMOLIGHT length"
                                                " N/A, verify")))
                            (if fl nil 2))))))
      ;; --- piece widths against the foam width.  This one DOES need
      ;;     the cover: a piece is bounded by the outline's edges.
      (if maxpiece
        (progn
          (if (> maxpiece (+ fw spachk:*foam-slack*))
            (setq rows (append rows
                        (list (spachk:row
                                (strcat "Foam width: widest piece "
                                        (spachk:dist maxpiece) " exceeds the "
                                        (spachk:dist fw) " sheet")
                                1))))
            (setq rows (append rows
                        (list (spachk:row
                                (strcat "Foam width: widest piece "
                                        (spachk:dist maxpiece) " within "
                                        (spachk:dist fw) ", OK")
                                nil))))))
        (setq rows (append rows
                    (list (spachk:row
                            (strcat "Foam width: not checked - no cover"
                                    " outline to measure the pieces against")
                            2)))))
      ;; --- the arrangement against the chart
      (setq want (spachk:hingetypes n allvel)
            got (mapcar '(lambda (e)
                           (if (spachk:has (spachk:hinge-label e labels)
                                           spachk:*velcro-word*)
                               "V" "H"))
                        sorted))
      (if (equal want got)
        (setq rows (append rows
                    (list (spachk:row
                            (strcat "Arrangement: "
                                    (spachk:join got " ") ", matches the"
                                    " Hinge Arrangement Chart")
                            nil))))
        (setq rows (append rows
                    (list (spachk:row
                            (strcat "Arrangement: reads "
                                    (spachk:join got " ")
                                    " but the chart says "
                                    (spachk:join want " ")
                                    " for " (itoa n) " pieces")
                            1)))
              ents (append ents sorted)))
      ;; --- every hinge must be labelled
      (setq k 0)
      (foreach e sorted
        (setq k (1+ k))
        (if (null (spachk:hinge-label e labels))
          (setq rows (append rows
                      (list (spachk:row
                              (strcat "Hinge " (itoa k)
                                      ": NO label on layer "
                                      spachk:*lay-text*)
                              1)))
                ents (cons e ents))))
      ;; --- hardware called for by the longest hinge (advice)
      (setq hw nil)
      (foreach h spachk:*hardtab*
        (if (and (not hw) (= (car h) grade)) (setq hw h)))
      (if hw
        (progn
          (setq k 0)
          (foreach nm (list "Velcro hinges" "Double C channel"
                            "Hold down kit")
            (setq vd (spachk:hardverdict (nth (1+ k) hw) maxrun))
            ;; only a YES is advice worth colouring -- a "no" is the
            ;; ordinary answer, and three cyan lines saying nothing is
            ;; needed would bury the one that says something is
            (setq rows (append rows
                        (list (spachk:row
                                (strcat nm ": "
                                        (if (car vd) "YES" "no")
                                        " - " (cdr vd))
                                (if (car vd) 2 nil)))))
            (setq k (1+ k)))))
      (spachk:res rows ents))))

;;; --- 6. the title block -------------------------------------------------

(defun spachk:audit-title (ss / r v)
  (setq r (spachk:border-box ss)
        v (spachk:title-verdict (car r)))
  (spachk:res
    (append
      (list (spachk:row (strcat "Title block: " (car v))
                        (if (cdr v) nil 1)))
      (if (and r (> (cdr r) 1))
        (list (spachk:row (strcat "Title block: " (itoa (cdr r))
                                  " separate borders on layer '"
                                  spachk:*border-layer*
                                  "' - the one nearest the spa was measured")
                          2))))
    nil))

;;; --- feet-and-inch text -------------------------------------------------
;;;  A distance written in feet must state its inches too: 5' is wrong,
;;;  5'-0" (or 5'-0'') is right, and a plain 40" is right as it stands.

;; A FEET MARK is an apostrophe standing straight after a DIGIT, and
;; that is what keeps prose out of this: "Water's Edge", "Owner's" and
;; "don't" are possessives, not measurements, and are never flagged.
;; Two apostrophes together are the inch mark AutoCAD text often uses
;; in place of ", so 5'-0'' closes exactly as 5'-0" does.
;;
;; T when some feet mark in s is never closed by an inch mark before
;; the next feet mark or the end of the string -- so "5' and 7'-0"" is
;; caught on its first value while "3'-2"" passes.
(defun spachk:feet-open-p (s / lst n i c prev open found)
  (setq lst   (vl-string->list s)
        n     (length lst)
        i     0
        prev  0
        open  nil
        found nil)
  (while (< i n)
    (setq c (nth i lst))
    (cond
      ((= c 34)                                    ; " closes it
       (setq open nil i (1+ i)))
      ((and (= c 39) (< (1+ i) n) (= (nth (1+ i) lst) 39))
       (setq open nil i (+ i 2)))                  ; '' closes it too
      ((and (= c 39) (>= prev 48) (<= prev 57))    ; digit then ' = feet
       (if open (setq found T))                    ; the one before never closed
       (setq open T i (1+ i)))
      (t (setq i (1+ i))))
    (setq prev (nth (1- i) lst)))
  (or found open))

(defun spachk:clip (s n)
  (if (> (strlen s) n) (strcat (substr s 1 n) "...") s))

;; MTEXT reads \, { and } as formatting, so a snippet quoted out of the
;; drawing has them blanked before it goes anywhere near the report.
(defun spachk:mtsafe (s)
  (vl-list->string
    (mapcar '(lambda (c) (if (member c '(92 123 125)) 32 c))
            (vl-string->list s))))

;; The text an entity carries: TEXT and ATTRIB keep it in group 1,
;; MTEXT spills the overflow into group 3 chunks ahead of that.
(defun spachk:ent-text (ent / ed g head tail)
  (setq ed (entget ent) head "" tail "")
  (foreach g ed
    (cond ((= 3 (car g)) (setq head (strcat head (cdr g))))
          ((= 1 (car g)) (setq tail (cdr g)))))
  (strcat head tail))

;; Every text box in the selection: TEXT and MTEXT, plus the ATTRIB
;; values on blocks -- the parts of a block someone types into.  Text
;; baked into a block DEFINITION is left alone: it reads the same on
;; every insert and is not fixable from this drawing.
(defun spachk:text-items (ss / i e ed et out a ad)
  (setq i 0)
  (if ss
    (repeat (sslength ss)
      (setq e  (ssname ss i)
            i  (1+ i)
            ed (entget e)
            et (if ed (cdr (assoc 0 ed))))
      (cond
        ((member et '("TEXT" "MTEXT"))
         (setq out (cons (cons (cdr (assoc 5 ed)) (spachk:ent-text e)) out)))
        ((and (= et "INSERT") (assoc 66 ed) (= 1 (cdr (assoc 66 ed))))
         (setq a (entnext e))
         (while (and a (setq ad (entget a)) (= "ATTRIB" (cdr (assoc 0 ad))))
           (setq out (cons (cons (cdr (assoc 5 ad)) (spachk:ent-text a)) out)
                 a   (entnext a)))))))
  (reverse out))

;; The verdict over every text box, then one row per offender.  The
;; report itself is skipped: SPACHECK writes it onto its own layer, but
;; a rerun reads the drawing before clearing the old one.
(defun spachk:audit-units (ss / items it s n bad rows)
  (setq items (spachk:text-items ss) n 0 bad 0 rows nil)
  (foreach it items
    (setq s (cdr it))
    (if (and s (/= s ""))
      (progn
        (setq n (1+ n))
        (if (spachk:feet-open-p s)
          (setq bad  (1+ bad)
                rows (append rows
                       (list (spachk:row
                               (strcat "Text " (car it) ": \""
                                       (spachk:mtsafe (spachk:clip s 40))
                                       "\" gives feet with NO INCHES"
                                       " - write it 5'-0\" not 5'")
                               1))))))))
  (spachk:res
    (cons (spachk:row
            (cond
              ((= n 0) "Feet & inches: no text in the selection")
              ((= bad 0) (strcat "Feet & inches: all " (itoa n) " text item"
                                 (if (= 1 n) "" "s") " OK"))
              (t (strcat "Feet & inches: " (itoa bad) " of " (itoa n)
                         " text item" (if (= 1 n) "" "s")
                         " give feet with NO INCHES"
                         " - write 5'-0\" not 5'")))
            (if (> bad 0) 1 nil))
          rows)
    nil))

;;; --- the Tech Title date ------------------------------------------------
;;;  The sheet's Tech Title block carries a Date attribute, and it must
;;;  read TODAY in MM/DD/YYYY form.  A sheet going out under an old date
;;;  is the mistake this catches: the drawing was reworked and the title
;;;  block never caught up -- so SPACHECK writes today's date over a
;;;  wrong one rather than leaving it to be noticed, in the same
;;;  MM/DD/YYYY form and with any label in front of it kept.  The scans
;;;  are read-only and only say so.

(defun spachk:pad2 (n)
  (if (< n 10) (strcat "0" (itoa n)) (itoa n)))

;; uppercase with every non-alphanumeric dropped, so "Tech Title"
;; matches a block actually named "TECHTITLE" or "Tech-Title"
(defun spachk:squash (s)
  (vl-list->string
    (vl-remove nil
      (mapcar '(lambda (c)
                 (cond ((and (>= c 48) (<= c 57)) c)
                       ((and (>= c 65) (<= c 90)) c)
                       ((and (>= c 97) (<= c 122)) (- c 32))))
              (vl-string->list (if s s ""))))))

;; the block's effective name, so a dynamic block answers by the name
;; it was drawn from rather than its anonymous one
(defun spachk:block-name (ent / res)
  (setq res (vl-catch-all-apply
              'vla-get-EffectiveName
              (list (vlax-ename->vla-object ent))))
  (if (vl-catch-all-error-p res) (spachk:dxf 2 ent) res))

(defun spachk:ins-attrib (ent tag)
  (cdr (assoc (strcase tag) (spachk:attribs ent))))

;; a value may arrive labelled ("Date: 05/01/2024" or "Date = ..."),
;; so the date is whatever follows the last "=" and then the last ":"
(defun spachk:after-eq (s / p)
  (while (setq p (vl-string-search "=" s))
    (setq s (substr s (+ p 2))))
  s)

(defun spachk:datenorm (s)
  (spachk:aftercolon (spachk:after-eq (if s s ""))))

(defun spachk:all-digits-p (s / i n c ok)
  (setq n (strlen s) ok (> n 0) i 1)
  (while (and ok (<= i n))
    (setq c (ascii (substr s i 1)))
    (if (or (< c 48) (> c 57)) (setq ok nil))
    (setq i (1+ i)))
  ok)

(defun spachk:days-in-month (mo yr)
  (cond
    ((member mo '(1 3 5 7 8 10 12)) 31)
    ((member mo '(4 6 9 11)) 30)
    ((and (= 0 (rem yr 4)) (or (/= 0 (rem yr 100)) (= 0 (rem yr 400)))) 29)
    (t 28)))

(defun spachk:today-mdy ( / d)
  ;; (month day year) off the computer clock.  CDATE is
  ;; YYYYMMDD.HHMMSSmsec, decoded arithmetically so DIMZIN (which trims
  ;; rtos output) cannot mangle it.
  (setq d (fix (getvar "CDATE")))
  (list (rem (fix (/ d 100)) 100) (rem d 100) (fix (/ d 10000))))

(defun spachk:mdy-str (mdy)
  (strcat (spachk:pad2 (car mdy)) "/" (spachk:pad2 (cadr mdy)) "/"
          (itoa (caddr mdy))))

;; nil when raw is today's date written MM/DD/YYYY; otherwise a short
;; string saying what is wrong with it.
(defun spachk:date-verdict (raw / s mo dd yr now)
  (setq s (spachk:trim (spachk:datenorm raw)))
  (cond
    ((= s "") "is blank - expected MM/DD/YYYY")
    ((or (/= (strlen s) 10)
         (/= (substr s 3 1) "/")
         (/= (substr s 6 1) "/")
         (not (spachk:all-digits-p (substr s 1 2)))
         (not (spachk:all-digits-p (substr s 4 2)))
         (not (spachk:all-digits-p (substr s 7 4))))
     (strcat "'" s "' is not in MM/DD/YYYY format - expected MM/DD/YYYY"))
    (t
     (setq mo (atoi (substr s 1 2))
           dd (atoi (substr s 4 2))
           yr (atoi (substr s 7 4)))
     (cond
       ((or (< mo 1) (> mo 12))
        (strcat "'" s "' - " (substr s 1 2)
                " is not a month (01-12) - expected MM/DD/YYYY"))
       ((or (< dd 1) (> dd (spachk:days-in-month mo yr)))
        (strcat "'" s "' - " (substr s 4 2)
                " is not a valid day for that month - expected MM/DD/YYYY"))
       ((progn (setq now (spachk:today-mdy))
               (not (and (= mo (car now)) (= dd (cadr now))
                         (= yr (caddr now)))))
        (strcat "'" s "' is NOT TODAY'S DATE (" (spachk:mdy-str now) ")"))
       (t nil)))))

;; Everything up to and including the last "=", "" when there is none:
;; the label a date arrives wearing ("Date = 05/01/2024"), so rewriting
;; the date keeps the wording in front of it.
(defun spachk:before-eq (s / p n)
  (setq n 0)
  (while (setq p (vl-string-search "=" (substr s (1+ n))))
    (setq n (+ n p 1)))
  (if (> n 0) (substr s 1 n) ""))

;; raw with today's date, written MM/DD/YYYY, in place of whatever date
;; it held; a "Date =" label in front of it is left as typed.
(defun spachk:date-fixed (raw / pre)
  (setq pre (spachk:before-eq raw))
  (if (= pre "")
    (spachk:mdy-str (spachk:today-mdy))
    (strcat pre " " (spachk:mdy-str (spachk:today-mdy)))))

;; Write val into the block reference's attribute with that tag; nil
;; when it carries no such attribute.
(defun spachk:set-attrib (ent tag val / e ed done)
  (setq tag (strcase tag)
        e   (entnext ent))
  (while (and e (null done) (setq ed (entget e))
              (= "ATTRIB" (cdr (assoc 0 ed))))
    (if (= tag (strcase (cdr (assoc 2 ed))))
      (if (entmod (subst (cons 1 val) (assoc 1 ed) ed))
        ;; entmod answers nil on a LOCKED layer and changes nothing:
        ;; done only when the value really went in, or the report
        ;; says "UPDATED" over a date still standing on the sheet
        (progn (entupd e) (setq done T))))
    (setq e (entnext e)))
  (if done (entupd ent))
  done)

;; Every Tech Title block in a selection set, in order.
(defun spachk:titles-in (ss pat / i e out)
  (setq i 0)
  (if ss
    (repeat (sslength ss)
      (setq e (ssname ss i) i (1+ i))
      (if (and (entget e) (= "INSERT" (spachk:etype e))
               (wcmatch (spachk:squash (spachk:block-name e)) pat))
        (setq out (cons e out)))))
  (reverse out))

;; The Tech Title block, looked for in the selection and then across
;; the drawing, since the title block sits outside the area someone
;; highlights as often as not.  Returns (title number-in-reach).  Of
;; several, the one nearest the spa is read: the FIRST one found used
;; to win, so in a drawing with two sheets the date was read off --
;; and SPACHECK wrote today's into -- whichever sheet's title the
;; database listed first.
(defun spachk:title-pick (ss / pat all f best bestd d e p)
  (setq pat (strcat "*" (spachk:squash spachk:*techtitle-block*) "*")
        all (spachk:titles-in ss pat))
  (if (null all)
    (setq all (spachk:titles-in (ssget "_X" '((0 . "INSERT"))) pat)))
  (setq f (if (cdr all) (spachk:focus ss)))
  (foreach e all
    (setq p (spachk:dxf 10 e)
          d (if (and f p) (distance f (list (car p) (cadr p))) 0.0))
    (if (or (null bestd) (< d bestd))
      (setq bestd d best e)))
  (if best (list best (length all))))

;; With no Tech Title in reach there is nothing to read, and that is
;; said plainly rather than flagged -- a spa sheet may well be checked
;; on its own, away from the sheet it will sit on.  With more than one
;; in reach the nearest is read and named, and nothing is WRITTEN: the
;; nearest is a good guess for reading and a bad one for rewriting
;; another sheet's title block.
(defun spachk:audit-date (ss dofix / pick blk n raw bad wrote p)
  (setq pick (spachk:title-pick ss)
        blk  (car pick)
        n    (cadr pick))
  (if (null blk)
    (spachk:res
      (list (spachk:row (strcat "Tech Title: no '" spachk:*techtitle-block*
                                "' block in reach - date NOT CHECKED")
                        nil))
      nil)
    (progn
      (setq raw (spachk:ins-attrib blk spachk:*date-tag*)
            bad (if raw
                  (spachk:date-verdict raw)
                  "is missing from the block - expected MM/DD/YYYY"))
      ;; SPACHECK does not leave a wrong date for someone to notice: it
      ;; writes today's over it in the same MM/DD/YYYY form, keeping any
      ;; label in front of it.  Only an attribute can be written, and
      ;; only when the caller is the fixing command -- the scans read.
      (if (and bad dofix (= n 1))
        (setq wrote (spachk:set-attrib blk spachk:*date-tag*
                                     (spachk:date-fixed (if raw raw "")))))
      (setq p (spachk:dxf 10 blk))
      (spachk:res
        (append
          (if (> n 1)
            (list (spachk:row
                    (strcat "Tech Title: " (itoa n) " '"
                            spachk:*techtitle-block* "' blocks in reach -"
                            " read the one at " (rtos (car p) 2 1) ","
                            (rtos (cadr p) 2 1) ", nearest the spa")
                    2)))
          (list (spachk:row
                  (cond
                    (wrote (strcat "Tech Title: " spachk:*date-tag* " " bad
                                 " - UPDATED to "
                                 (spachk:mdy-str (spachk:today-mdy))))
                    ((and bad (> n 1))
                     (strcat "Tech Title: " spachk:*date-tag* " " bad
                             " - NOT UPDATED: highlight the spa with its"
                             " own Tech Title and run SPACHECK"))
                    ((and bad dofix)
                     (strcat "Tech Title: " spachk:*date-tag* " " bad
                             " - fix it in the block"))
                    (bad (strcat "Tech Title: " spachk:*date-tag* " " bad
                                 " - NEEDS UPDATING (run SPACHECK)"))
                    (t (strcat "Tech Title: " spachk:*date-tag* " = '"
                               (spachk:trim (spachk:datenorm raw)) "' - OK")))
                  (if bad 1 nil))))
        nil))))

;;; ======================================================================
;;;  RUNNING THE AUDIT
;;; ======================================================================

;; Everything, in report order, each section under its heading row.
;; The mechanical per-dimension audit (layer, style, span agreement)
;; is DIMCHECK's ground, so its rows come back separately for the
;; report's second column - and a lite run skips it altogether.
;; Returns (main-rows dim-rows flagged-entities).
(defun spachk:audit (ss lite dofix / rows drows ents blk att g tp cov wat covo
                                 wato dims covn hngs r covbb watbb fr)
  (setq rows nil drows nil ents nil)

  ;; 1 -- the block
  (setq rows (append rows (list (spachk:row "THE DETAILS BLOCK" 3))))
  (setq r (spachk:audit-block ss)
        rows (append rows (spachk:res-rows r))
        ents (append ents (spachk:res-ents r)))
  (setq blk (spachk:find-details ss)
        att (if blk (spachk:attribs blk) nil)
        g   (spachk:gradenorm (if (cdr (assoc "GRADE" att))
                                  (spachk:aftercolon (cdr (assoc "GRADE" att)))
                                  nil))
        tp  (if (cdr (assoc "TAPER" att))
                (spachk:tapernorm (spachk:aftercolon (cdr (assoc "TAPER" att))))
                nil))
  (if (and (= g "THERMOLIGHT") (null tp)) (setq tp "1-3/8"))

  ;; 2 -- the cover outline
  (setq rows (append rows (list (spachk:row "THE OUTLINES" 3))))
  (setq r (spachk:audit-outline ss spachk:*lay-cover* "Cover outline" t)
        rows (append rows (spachk:res-rows r))
        ents (append ents (spachk:res-ents r))
        covo (spachk:outline-ents ss spachk:*lay-cover*)
        cov  (if (= 1 (length covo)) (car covo) nil))
  ;; the cover's own frame -- its edges' direction, turned to the
  ;; quarter of the UCS its dimensions were made in (group 51,
  ;; spachk:cover-frame): nil, World, for a cover SPA drew in World --
  ;; and its box in that frame, resolved ONCE here and threaded down to
  ;; every sibling below instead of each re-resolving it off cov itself
  (setq dims  (spachk:dims ss)
        covn  (spachk:dims-noted dims spachk:*sfx-cover*)
        hngs  (spachk:hinge-lines ss)
        fr    (spachk:cover-frame cov covn dims hngs)
        covbb (if cov (spachk:fr-box cov fr)))

  ;; 3 -- the water's edge outline
  (setq r (spachk:audit-outline ss spachk:*lay-water* "Water's edge" nil)
        rows (append rows (spachk:res-rows r))
        ents (append ents (spachk:res-ents r))
        wato (spachk:outline-ents ss spachk:*lay-water*)
        wat  (if (= 1 (length wato)) (car wato) nil))
  (setq watbb (if wat (spachk:fr-box wat fr)))

  (setq r (spachk:audit-nesting covbb watbb)
        rows (append rows (spachk:res-rows r)))

  ;; 4 -- the dimensions.  The per-dimension audit fills the second
  ;; column; the roster and standoffs are SPA's own rules and stay on
  ;; the main sheet.
  (setq rows (append rows (list (spachk:row "THE OVERALLS" 3))))
  ;; the dimension-layer verdict runs in every mode, lite included
  (setq r (spachk:audit-dimlayer dims)
        rows (append rows (spachk:res-rows r)))
  (if (not lite)
    (setq r     (spachk:audit-dims dims cov wat)
          drows (spachk:res-rows r)
          ents  (append ents (spachk:res-ents r))))
  (setq r (spachk:audit-roster dims cov wat covbb watbb fr)
        rows (append rows (spachk:res-rows r))
        ents (append ents (spachk:res-ents r)))
  (setq r    (spachk:audit-standoff-in covn covbb fr)
        rows (append rows (spachk:res-rows r)))

  ;; 5 -- the hinges (only meaningful with a taper)
  (setq rows (append rows (list (spachk:row "THE HINGES" 3))))
  (if tp
    (progn
      (setq r (spachk:audit-hinges ss hngs covbb g tp fr)
            rows (append rows (spachk:res-rows r))
            ents (append ents (spachk:res-ents r))))
    (setq rows (append rows
                (list (spachk:row
                        "Hinges: not checked - no taper to check against"
                        1)))))

  ;; 6 -- the text boxes: feet must carry inches (every mode, lite too)
  (setq rows (append rows (list (spachk:row "TEXT & UNITS" 3))))
  (setq r (spachk:audit-units ss)
        rows (append rows (spachk:res-rows r)))

  ;; 7 -- the Tech Title date (every mode, lite too)
  (setq rows (append rows (list (spachk:row "THE TECH TITLE" 3))))
  (setq r (spachk:audit-date ss dofix)
        rows (append rows (spachk:res-rows r)))

  ;; 8 -- the title block
  (setq rows (append rows (list (spachk:row "THE TITLE BLOCK" 3))))
  (setq r (spachk:audit-title ss)
        rows (append rows (spachk:res-rows r)))

  (list rows drows ents))

;;; -------------------- the report --------------------------------------

;; The whole report: the SPA-specific findings on the MAIN sheet and,
;; unless lite, the per-dimension audit in a DIMENSION AUDIT column to
;; its right - the DIMCHECK-style pass, set apart so the spa verdicts
;; lead.  Returns (problem-count advisory-count), over both columns.
(defun spachk:write-report (rows drows bb readonly lite
                            / nlin ndim ref h ins ins2 txt r nbad nadv)
  (spachk:ensure-layer spachk:*report-layer* spachk:*report-color*)
  (setq nbad 0 nadv 0)
  (foreach r (append rows drows)
    (cond ((spachk:lvl-p r 1) (setq nbad (1+ nbad)))
          ((spachk:lvl-p r 2) (setq nadv (1+ nadv)))))
  ;; height: scale the sheet to the drawing, as the siblings do.  The
  ;; head is title (1.5) + date + verdict (1.2) + legend; a heading
  ;; row is one line plus the 0.4 gap above it.  The dimension column
  ;; is counted the same way, and the taller column drives the height.
  (setq nlin spachk:*head-lines*)
  (foreach r rows
    (setq nlin (+ nlin (cond ((spachk:lvl-p r 3) spachk:*hdg-lines*)
                             ((spachk:row-lvl r) 1.0)
                             (t spachk:*green-scale*)))))
  (setq ndim (+ spachk:*dim-head* (if drows (length drows) 1)))
  (if (and (not lite) (> ndim nlin)) (setq nlin ndim))
  (if (and bb (> (max (spachk:bw bb) (spachk:bh bb)) spachk:*tiny*))
    (progn
      (setq ref (max (spachk:bh bb)
                     (* spachk:*report-wide* (spachk:bw bb)))
            h   (/ ref (* spachk:*report-lead* nlin)))
      (if (> h (/ ref spachk:*report-hmax*))
        (setq h (/ ref spachk:*report-hmax*)))
      (if (< h (/ ref spachk:*report-hmin*))
        (setq h (/ ref spachk:*report-hmin*))))
    (setq h spachk:*report-hfall*))
  (setq ins (if bb
                (list (+ (caadr bb)
                         (* spachk:*report-gap* (max (spachk:bw bb) 1.0)))
                      (cadadr bb) 0.0)
                (list 0.0 0.0 0.0)))
  ;; the head: a large title, the date and version small under it, a
  ;; verdict line -- red with the problem count, cyan when only advice,
  ;; plain ALL CLEAR otherwise -- then the colour legend.  The verdict
  ;; is wrapped in its height code first so it never renders as (or
  ;; counts among) the finding rows, which start with a colour code.
  (setq txt (strcat (spachk:big (cond ((and readonly lite)
                                       "LITESPACHECKSCAN REPORT")
                                      (readonly "SPACHECKSCAN REPORT")
                                      (t "SPACHECK REPORT")))
                    "\\P"
                    (spachk:small (strcat (spachk:datestr)
                                          "  -  SPACHECK "
                                          *spacheck-version*))
                    "\\P"
                    "{\\H1.2x;"
                    (cond
                      ((> nbad 0)
                       (spachk:red
                         (strcat (itoa nbad) " PROBLEM"
                                 (if (= 1 nbad) "" "S")
                                 (if (> nadv 0)
                                     (strcat ", " (itoa nadv) " ADVISOR"
                                             (if (= 1 nadv) "Y" "IES"))
                                     ""))))
                      ((> nadv 0)
                       (spachk:cyan
                         (strcat "ALL CLEAR - " (itoa nadv) " advisor"
                                 (if (= 1 nadv) "y" "ies"))))
                      (t "ALL CLEAR - every check passed"))
                    "}"
                    "\\P"
                    (spachk:small
                      (strcat (if readonly
                                  "Read-only scan - nothing in the drawing was changed.  "
                                  "")
                              (if lite
                                  "Lite: the dimension audit was skipped - run SPACHECKSCAN or DIMCHECK for it.  "
                                  "")
                              "Problems in " (spachk:red "red")
                              ", advice in " (spachk:cyan "cyan")
                              "; lines that checked out are smaller."))))
  (foreach r rows
    (setq txt (strcat txt "\\P" (spachk:render r))))
  (spachk:mtext ins h (* spachk:*report-chars* h) txt spachk:*report-layer*)
  ;; the DIMENSION AUDIT column, to the right of the main sheet
  (if (not lite)
    (progn
      (setq ins2 (list (+ (car ins)
                          (* (+ spachk:*report-chars* spachk:*col-gap*) h))
                       (cadr ins) 0.0)
            txt  (strcat "{\\H1.2x;DIMENSION AUDIT}"
                         "\\P"
                         (spachk:small
                           (strcat "Each dimension against its layer, its"
                                   " style and its own span - DIMCHECK's"
                                   " ground, kept off the main sheet."))))
      (if drows
        (foreach r drows
          (setq txt (strcat txt "\\P" (spachk:render r))))
        (setq txt (strcat txt "\\P"
                          (spachk:small "  Every dimension checks out."))))
      (spachk:mtext ins2 h (* spachk:*report-chars* h) txt
                    spachk:*report-layer*)))
  (list nbad nadv))

;;; -------------------- marking (SPACHECK only) -------------------------

(defun spachk:regapp ()
  (if (not (tblsearch "APPID" "SPACHECK")) (regapp "SPACHECK")))

;; T when the layer named is LOCKED, where entmod answers nil and
;; entdel refuses.
(defun spachk:layer-locked-p (lay / rec)
  (setq rec (if lay (tblsearch "LAYER" lay)))
  (and rec (= 4 (logand 4 (cdr (assoc 70 rec))))))

;; T when ent sits on a LOCKED layer.
(defun spachk:locked-p (ent)
  (spachk:layer-locked-p (spachk:layer ent)))

;; The tail a completion line carries for writes AutoCAD refused:
;; ", 2 NOT recoloured (their layers are locked)".  n were refused and
;; nlock of them sit on a locked layer -- a refusal is blamed on a lock
;; only when the layer really is locked, since entmod answers nil for
;; other reasons too.  "" when nothing was refused.
(defun spachk:refused-tail (n nlock what)
  (if (> n 0)
    (strcat ", " (itoa n) " NOT " what
            (cond ((<= nlock 0) "")
                  ((and (= nlock n) (= n 1)) " (its layer is locked)")
                  ((= nlock n) " (their layers are locked)")
                  (t (strcat " (" (itoa nlock) " on "
                             (if (= nlock 1) "a locked layer"
                                             "locked layers")
                             ")"))))
    ""))

;; Remember the entity's own colour in xdata so SPACHECKRESCUE can put
;; it back even after a crash; an existing stash (from an interrupted
;; run - the TRUE original) is never overwritten.  Non-nil only when
;; the item really went red: on a locked layer both writes are refused,
;; and the walk used to count "1 item marked red" over an item that
;; never changed colour.  The stash and the colour go in together or
;; not at all -- a colour with no stash is one RESCUE cannot put back.
(defun spachk:stash-color (ent col / ed cur ok fresh)
  (spachk:regapp)
  (setq ed  (entget ent '("SPACHECK"))
        cur (cdr (assoc 62 (entget ent)))
        ok  (and ed (not (spachk:locked-p ent))))
  (if (and ok (not (assoc -3 ed)))
    (setq fresh T
          ok    (entmod (append ed (list (list -3 (list "SPACHECK"
                                                  '(1000 . "COLOR")
                                                  (cons 1071
                                                        (if cur cur 256)))))))))
  ;; now recolour it
  (if ok
    (progn
      (setq ed (entget ent)
            ok (entmod (if (assoc 62 ed)
                           (subst (cons 62 col) (assoc 62 ed) ed)
                           (append ed (list (cons 62 col))))))
      ;; a stash this call wrote for a colour that did not go in comes
      ;; out again, so RESCUE never counts an item it never changed
      (if (and fresh (not ok))
        (progn
          (setq ed (entget ent '("SPACHECK")))
          (entmod (subst (list -3 (list "SPACHECK")) (assoc -3 ed) ed))))
      (entupd ent)))
  ok)

;; Put a stashed colour back and drop the xdata.  T when it did both,
;; 'refused when the entity's layer would not take the writes -- the
;; stash is then left in place, so a RESCUE run after the layer is
;; unlocked still finds it -- and nil when there was nothing stashed.
(defun spachk:unstash (ent / ed xd old ok)
  (setq ed (entget ent '("SPACHECK"))
        xd (if (assoc -3 ed) (cdadr (assoc -3 ed)) nil))
  (if xd
    (progn
      (setq old (cdr (assoc 1071 xd))
            ok  (not (spachk:locked-p ent)))
      (if (and ok old)
        (progn
          (setq ed (entget ent)
                ok (entmod (if (= old 256)
                               (if (assoc 62 ed)
                                   (vl-remove (assoc 62 ed) ed)
                                   ed)
                               (if (assoc 62 ed)
                                   (subst (cons 62 old) (assoc 62 ed) ed)
                                   (append ed (list (cons 62 old)))))))))
      (if ok
        (progn
          (setq ed (entget ent '("SPACHECK"))
                ok (entmod (subst (list -3 (list "SPACHECK"))
                                  (assoc -3 ed) ed)))
          (entupd ent)))
      (if ok T 'refused))))

(defun spachk:zoom-ent (ent / bb p1 p2 m)
  (if (setq bb (spachk:bbox ent))
    (progn
      (setq m  (* spachk:*zoom-margin*
                  (max (spachk:bw bb) (spachk:bh bb) 1.0))
            p1 (list (- (caar bb) m) (- (cadar bb) m) 0.0)
            p2 (list (+ (caadr bb) m) (+ (cadadr bb) m) 0.0))
      ;; the box is WCS and ZOOM reads the current UCS
      (command "_.ZOOM" "_Window" (trans p1 0 1) (trans p2 0 1)))))

;;; -------------------- asking ------------------------------------------
;;;  The section-4 helpers, embedded under this file's own prefix.

(defun spachk:askkw (msg kws hidden dflt back / v)
  (initget (if dflt 0 (if back 0 1))
           (strcat kws
                   (if hidden (strcat " " hidden) "")
                   (if back " Back Undo" "")))
  (setq v (getkword (strcat "\n" msg " ["
                            (vl-string-translate " " "/" kws)
                            (if back "/Back" "") "]"
                            (if dflt (strcat " <" dflt ">") "") ": ")))
  (if lzd:ask (lzd:ask msg v) v)
  (cond ((member v '("Back" "Undo")) 'SPACHK-BACK)
        ((null v) (if dflt dflt (spachk:askkw msg kws hidden dflt back)))
        (t v)))

;;; -------------------- sysvars -----------------------------------------

;; OSMODE is deliberately NOT in this list.  SPACHECK never
;; changes it, and a list is a promise to WRITE the value back: the run
;; would put its opening snapshot back over any snap the drafter ticked
;; on while it was up -- on a clean exit, with no error involved, which
;; is the likeliest way anyone meets it.  Borrow only what you move.
;; No CLAYER either: SPACHECK draws nothing on the current layer, only
;; the tutorial's demo does, and that one saves and puts back its own
;; (c:TUTORIALSPACHECK's oldlay) -- listing it here would put the
;; review's opening layer back over one the drafter switched to while
;; walking the items.  tools/check_color.py holds this the way
;; check_osnap holds OSMODE.
(defun spachk:syssave ()
  (if (not spachk:*sysold*)
    (setq spachk:*sysold*
          (mapcar '(lambda (v) (cons v (getvar v)))
                  '("CMDECHO")))))

(defun spachk:sysrestore ( / v p)
  (foreach v '("CMDECHO")
    (setq p (assoc v spachk:*sysold*))
    (if p (setvar v (cdr p))))
  (setq spachk:*sysold* nil))

;;; ======================================================================
;;;  COMMANDS
;;; ======================================================================

(defun c:SPACHECKVER ()
  (princ (strcat "\nSPACHECK " *spacheck-version*))
  (princ (strcat "\n  spa title block: " (rtos spachk:*title-frac* 2 2)
                 "x the liner block = "
                 (rtos (* spachk:*title-frac* spachk:*liner-w*)) " x "
                 (rtos (* spachk:*title-frac* spachk:*liner-h*))))
  (princ))

;;; --- SPACHECKSCAN / LITESPACHECKSCAN: the audits, read-only ------------
;;;  The lite scan is the same audits minus the per-dimension pass,
;;;  for a drawing DIMCHECK already went over.

(defun c:SPACHECKSCAN () (spachk:scan nil))

(defun c:LITESPACHECKSCAN () (spachk:scan T))

(defun spachk:scan (lite / *error* oldecho name ss res rows drows bb ents n)
  (setq name (if lite "LITESPACHECKSCAN" "SPACHECKSCAN"))
  (defun *error* (msg)
    (if oldecho (setvar "CMDECHO" oldecho))
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\n" name " error: " msg)))
    (if lzd:report (lzd:report "SPACHECK" *spacheck-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "SPACHECK" *spacheck-version*))
  ;; a pickfirst selection if there is one, otherwise ask for it
  (setq ss (ssget "_I"))
  (if lzd:watch (lzd:watch ss) ss)
  (if (null ss)
    (progn
      (prompt (strcat "\nHighlight the spa drawing and its "
                      spachk:*details-block*
                      " block to " name " (Enter = whole drawing): "))
      (setq ss (ssget))
      (if lzd:watch (lzd:watch ss) ss)))
  ;; Enter: the space the drafter is working in.  A bare "_X" took every
  ;; layout's paper-space ink as well, and a sheet border or a paper
  ;; dimension crossing the spa's coordinates could make a stray point
  ;; read as attached
  (if (null ss) (setq ss (ssget "_X" (list (cons 410 (spachk:space))))))
  (if (null ss)
    (prompt "\nNothing to scan.")
    (progn
      (setq oldecho (getvar "CMDECHO"))
      (setvar "CMDECHO" 0)
      (setq res   (spachk:audit ss lite nil)
            rows  (car res)
            drows (cadr res)
            ents  (caddr res)
            bb    (spachk:bbox-of (spachk:outline-ents ss spachk:*lay-cover*))
            n     (spachk:write-report rows drows bb t lite))
      (setvar "CMDECHO" oldecho)
      (princ (strcat "\n--- " name " complete (read-only) ---"
                     "\n" (itoa (car n)) " problem"
                     (if (= 1 (car n)) "" "s") ", "
                     (itoa (cadr n)) " advisor"
                     (if (= 1 (cadr n)) "y" "ies")
                     (if lite
                         "\nLite: the dimension audit was skipped."
                         "")
                     "\nReport written on layer " spachk:*report-layer*
                     "; nothing else was changed."))))
  (if lzd:end (lzd:end "SPACHECK"))
  (princ))

;;; --- SPACHECK: the audits, then a walk of what they flagged ------------

(defun c:SPACHECK ( / *error* oldecho undo-open ss res rows drows ents bb n
                      e k tot ans marked nref nlock)
  (defun *error* (msg)
    (spachk:sysrestore)
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nSPACHECK error: " msg)))
    (if lzd:report (lzd:report "SPACHECK" *spacheck-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "SPACHECK" *spacheck-version*))
  ;; a pickfirst selection if there is one, otherwise ask for it
  (setq ss (ssget "_I"))
  (if lzd:watch (lzd:watch ss) ss)
  (if (null ss)
    (progn
      (prompt (strcat "\nHighlight the spa drawing and its "
                      spachk:*details-block*
                      " block to SPACHECK (Enter = whole drawing): "))
      (setq ss (ssget))
      (if lzd:watch (lzd:watch ss) ss)))
  ;; Enter: the space the drafter is working in (see spachk:scan)
  (if (null ss) (setq ss (ssget "_X" (list (cons 410 (spachk:space))))))
  (if (null ss)
    (prompt "\nNothing to check.")
    (progn
      (spachk:syssave)
      (setq oldecho (getvar "CMDECHO"))
      (setvar "CMDECHO" 0)
      ;; only when undo is recording - _Begin in a drawing with UNDO
      ;; off (bit 1 of UNDOCTL clear) errors out of the command
      (if (= 1 (logand 1 (getvar "UNDOCTL")))
        (progn
          (command "_.UNDO" "_Begin")
          (setq undo-open T)))
      (setq res   (spachk:audit ss nil T)
            rows  (car res)
            drows (cadr res)
            ents  (caddr res)
            bb    (spachk:bbox-of (spachk:outline-ents ss spachk:*lay-cover*)))
      ;; walk what was flagged, one at a time
      (setq tot (length ents) k 0 marked 0 nref 0 nlock 0)
      (if (> tot 0)
        (progn
          (princ (strcat "\n" (itoa tot) " item"
                         (if (= 1 tot) "" "s")
                         " to look at, one at a time."))
          (foreach e ents
            (setq k (1+ k))
            (if (entget e)
              (progn
                (spachk:zoom-ent e)
                (setq ans (spachk:askkw
                            (strcat "  Item " (itoa k) " of " (itoa tot)
                                    " - mark it as wrong?")
                            "Yes No Skip" nil "No" nil))
                (cond
                  ((= ans "Yes")
                   (if (spachk:stash-color e spachk:*flag-color*)
                     (setq marked (1+ marked))
                     (progn
                       (setq nref (1+ nref))
                       (if (spachk:locked-p e)
                         (progn
                           (setq nlock (1+ nlock))
                           (princ (strcat "\n  On locked layer "
                                          (spachk:layer e)
                                          " - listed in the report, NOT"
                                          " recoloured.")))
                         (princ (strcat "\n  AutoCAD would not recolour"
                                        " it (layer " (spachk:layer e)
                                        ") - listed in the report."))))))
                  ((= ans "Skip") (setq k tot))))))))
      (setq n (spachk:write-report rows drows bb nil nil))
      (command "_.ZOOM" "_Extents")
      ;; closed only if one was opened -- the guard the handler above
      ;; already makes.  With undo recording off (UNDOCTL bit 1 clear)
      ;; there is no group of this run's, and an _End on nothing is an
      ;; error of its own: it would land here, with the report written
      ;; and every flagged item recoloured, and the CMDECHO and sysvar
      ;; putbacks below it never reached
      (if undo-open
        (progn
          (command "_.UNDO" "_End")
          (setq undo-open nil)))
      (setvar "CMDECHO" oldecho)
      (spachk:sysrestore)
      (princ (strcat "\n--- SPACHECK complete ---"
                     "\n" (itoa (car n)) " problem"
                     (if (= 1 (car n)) "" "s") ", "
                     (itoa (cadr n)) " advisor"
                     (if (= 1 (cadr n)) "y" "ies")
                     "\n" (itoa marked) " item"
                     (if (= 1 marked) "" "s") " marked red"
                     (spachk:refused-tail nref nlock "recoloured")
                     "\nReport written on layer " spachk:*report-layer*
                     ".  SPACHECKRESCUE puts the colours back."))))
  (if lzd:end (lzd:end "SPACHECK"))
  (princ))

;;; --- SPACHECKRESCUE: put every colour back -----------------------------

(defun c:SPACHECKRESCUE ( / *error* oldecho ss i e n r nref nlock kept)
  (defun *error* (msg)
    (if oldecho (setvar "CMDECHO" oldecho))
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nSPACHECKRESCUE error: " msg)))
    (if lzd:report (lzd:report "SPACHECKRESCUE" *spacheck-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "SPACHECKRESCUE" *spacheck-version*))
  (setq oldecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (setq ss (ssget "_X") i 0 n 0 nref 0 nlock 0 kept 0)
  (if ss
    (repeat (sslength ss)
      (setq e (ssname ss i) i (1+ i)
            r (spachk:unstash e))
      (cond ((eq r 'refused)
             (setq nref (1+ nref))
             (if (spachk:locked-p e) (setq nlock (1+ nlock))))
            (r (setq n (1+ n))))))
  ;; and the report itself -- entdel refuses on a locked layer too,
  ;; and a refusal is counted rather than allowed to end the run
  (setq ss (ssget "_X" (list (cons 8 spachk:*report-layer*))) i 0)
  (if ss
    (repeat (sslength ss)
      (setq r (vl-catch-all-apply 'entdel (list (ssname ss i))))
      (if (or (null r) (vl-catch-all-error-p r)) (setq kept (1+ kept)))
      (setq i (1+ i))))
  (setvar "CMDECHO" oldecho)
  ;; only what really changed is counted: a colour on a locked layer is
  ;; still wrong on the sheet, and the drafter has to be told where
  (princ (strcat "\nSPACHECKRESCUE: " (itoa n) " colour"
                 (if (= 1 n) "" "s") " put back"
                 (spachk:refused-tail nref nlock "put back")
                 (if (> nlock 0)
                   " - unlock and run SPACHECKRESCUE again"
                   "")
                 (cond ((= kept 0) ", report removed.")
                       ((spachk:layer-locked-p spachk:*report-layer*)
                        ", report NOT removed (its layer is locked).")
                       (t ", report NOT removed."))))
  (if lzd:end (lzd:end "SPACHECKRESCUE"))
  (princ))

;;; --- TUTORIALSPACHECK: every check spelled out -------------------------

(defun spachk:tut-checklist ()
  (list
    "WHAT SPACHECK CHECKS"
    ""
    "Highlight the spa drawing TOGETHER WITH its Spa Cover Details"
    "block.  Every audit below comes from what SPA.LSP actually draws,"
    "so a drawing SPA produced passes and a hand-edited one shows"
    "exactly where it drifted."
    ""
    "1. SPA COVER DETAILS BLOCK"
    "   One in the selection, with a readable TAPER tag.  A missing"
    "     GRADE is taken as Standard, the way SPA takes it."
    "   THERMOLIGHT must be the 1-3/8 flat taper."
    ""
    "2. THE COVER OUTLINE"
    (strcat "   Exactly one closed entity on layer " spachk:*lay-cover*
            " - one polyline,")
    "     or a circle/ellipse for a round spa.  Loose arcs there are"
    "     the old pre-bounded output and are reported."
    ""
    "3. THE WATER'S EDGE OUTLINE"
    (strcat "   Optional.  When drawn: one closed entity on layer "
            spachk:*lay-water* ",")
    "     and INSIDE the cover - the cover is always the larger."
    ""
    "4. THE DIMENSIONS"
    (strcat "   Every one on layer " spachk:*lay-dim* ", in the right style")
    (strcat "     (" spachk:*ds-cover* " for the cover's, "
            spachk:*ds-water* " for")
    "     the water's edge's), and agreeing with what it spans - a"
    "     dimension whose measurement does not match its own points is"
    "     reported with both numbers."
    (strcat "   Both overalls present and noted '" spachk:*sfx-cover* "',")
    "     reading the cover's true size, standing 2 ft above and 3 ft"
    "     to the left as SPA places them."
    (strcat "   With both outlines drawn, an '" spachk:*sfx-lap*
            "' dimension reading")
    "     the true lap."
    ""
    "5. THE HINGES"
    (strcat "   The LINEs on layer " spachk:*lay-cover*
            " (the outline is a polyline, so")
    "     the two never confuse).  Against the block's grade and taper:"
    "     the piece count must be one the taper allows, no piece wider"
    "     than the foam width, no hinge longer than the foam length,"
    "     the fold/velcro order must match the Hinge Arrangement Chart,"
    (strcat "     and every hinge must carry its label on layer "
            spachk:*lay-text* ".")
    "   Hardware by the longest hinge is reported as advice."
    ""
    "6. THE TITLE BLOCK"
    (strcat "   Everything on layer '" spachk:*border-layer*
            "' measured together, one frame")
    "     per sheet: with several sheets, the one nearest the spa."
    (strcat "   A spa title block is exactly "
            (rtos spachk:*title-frac* 2 2) "x the liner block "
            (rtos spachk:*liner-w*) " x " (rtos spachk:*liner-h*))
    (strcat "     = " (rtos (* spachk:*title-frac* spachk:*liner-w*)) " x "
            (rtos (* spachk:*title-frac* spachk:*liner-h*)) ".")
    "   Out of proportion is reported separately as STRETCHED."
    ""
    "7. THE REPORT"
    "   An MTEXT sheet to the right of the drawing, sized to scale with"
    (strcat "     it.  Problems in RED, advice in CYAN, all-clear at "
            (rtos (* 100.0 spachk:*green-scale*) 2 0) "%.")
    ""
    "COMMANDS"
    "   SPACHECK         audit, then walk what it flagged"
    "   SPACHECKSCAN     the same audits, read-only"
    "   SPACHECKVER      which revision is loaded"
    "   SPACHECKRESCUE   put every colour back, remove the report"
    ""
    "   TUTORIALSPACHECK Demo draws a practice spa with three faults"
    "                    planted in it and walks you through each one."))

;;; --- the demo ----------------------------------------------------------
;;;  A small practice spa drawn in an empty spot, with three faults
;;;  planted in it, walked through one at a time.  Everything it makes
;;;  goes in one list so the offer to erase it afterwards can be kept.

;; Remember one entity the demo made, and hand it straight back so the
;; caller can go on using it.
(defun spachk:demo-ent (e)
  (if e (setq spachk:*demo-ents* (cons e spachk:*demo-ents*)))
  e)

;; A closed rectangle, corners counter-clockwise from p.
(defun spachk:demo-rect (p w h layer / x y)
  (setq x (car p) y (cadr p))
  (spachk:demo-ent
    (entmakex (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity")
                    (cons 8 layer) '(100 . "AcDbPolyline")
                    '(90 . 4) '(70 . 1)
                    (list 10 x y) '(42 . 0.0)
                    (list 10 (+ x w) y) '(42 . 0.0)
                    (list 10 (+ x w) (+ y h)) '(42 . 0.0)
                    (list 10 x (+ y h)) '(42 . 0.0)))))

(defun spachk:demo-line (p q layer)
  (spachk:demo-ent
    (entmakex (list '(0 . "LINE") '(100 . "AcDbEntity") (cons 8 layer)
                    '(100 . "AcDbLine") (cons 10 p) (cons 11 q)))))

;; An aligned dim carrying a note, drawn the way SPA draws one.  The
;; points are WORLD, like everything else the demo entmakes, and a
;; command reads the current UCS -- so each goes through trans, or
;; under a moved UCS every practice dim floated off its rectangle and
;; the scan reported faults nobody planted.
(defun spachk:demo-dim (p1 p2 at note style / e)
  (spachk:dimstyle-set style)
  (setvar "CLAYER" spachk:*lay-dim*)
  ;; _non on every point: the whole demo turns on a dim that DISAGREES
  ;; with the geometry under it, and a live osnap would quietly pull it
  ;; onto the true corner and plant nothing at all
  (command "_.DIMALIGNED"
           "_non" (trans (list (car p1) (cadr p1) 0.0) 0 1)
           "_non" (trans (list (car p2) (cadr p2) 0.0) 0 1)
           "_T" (strcat "<>" note)
           "_non" (trans (list (car at) (cadr at) 0.0) 0 1))
  (if (setq e (entlast)) (spachk:demo-ent e))
  e)

;; The current dimension style is read-only to setvar, so it has its
;; own snapshot pair and restores through a command.  The demo SAVES a
;; missing style into the drawing (below), so leaving the style
;; switched would hand the user a sheet dimensioned in a style the
;; tutorial invented.  (From cal:dimstysave / cal:dimstyrestore.)
(defun spachk:dimstysave ()
  (if (not spachk:*odstyle*) (setq spachk:*odstyle* (getvar "DIMSTYLE"))))

(defun spachk:dimstyrestore ()
  ;; called from *error* too, where a bare (command ...) can itself
  ;; fail -- so command-s under vl-catch-all-apply (STANDARDS 5)
  (if (and spachk:*odstyle* (tblsearch "DIMSTYLE" spachk:*odstyle*))
    (vl-catch-all-apply 'command-s
      (list "_.-DIMSTYLE" "_Restore" spachk:*odstyle*)))
  (setq spachk:*odstyle* nil))

;; Make a dimension style current.  A drawing that has never held a spa
;; sheet has neither spa style in it, and a demo that then dimensioned
;; in STANDARD would report two style faults nobody planted -- so a
;; missing one is saved from the current settings, as SPA does.
(defun spachk:dimstyle-set (name)
  (if (tblsearch "DIMSTYLE" name)
    (command "_.-DIMSTYLE" "_Restore" name)
    (command "_.-DIMSTYLE" "_Save" name)))

;; A Spa Cover Details block, defined and inserted, carrying the GRADE
;; and TAPER the hinge checks read.  Without it the demo's unlabelled
;; hinge -- one of the three planted faults -- could never be reported,
;; because the hinge section stops for want of a taper.
(defun spachk:demo-block (p grade taper / e tag)
  (if (not (tblsearch "BLOCK" spachk:*details-block*))
    (progn
      (entmake (list '(0 . "BLOCK") '(100 . "AcDbEntity")
                     (cons 8 spachk:*lay-text*)
                     '(100 . "AcDbBlockBegin")
                     (cons 2 spachk:*details-block*)
                     '(70 . 2)                 ; has attribute definitions
                     '(10 0.0 0.0 0.0)))
      (foreach e (list (list "GRADE" 12.0) (list "TAPER" 0.0))
        (entmake (list '(0 . "ATTDEF") '(100 . "AcDbEntity")
                       (cons 8 spachk:*lay-text*) '(100 . "AcDbText")
                       (list 10 0.0 (cadr e) 0.0) '(40 . 5.0)
                       (cons 1 (car e)) '(100 . "AcDbAttributeDefinition")
                       (cons 3 (car e)) (cons 2 (car e)) '(70 . 0))))
      (entmake (list '(0 . "ENDBLK") '(100 . "AcDbEntity")
                     (cons 8 spachk:*lay-text*)
                     '(100 . "AcDbBlockEnd")))))
  (setq e (spachk:demo-ent
            (entmakex (list '(0 . "INSERT") '(100 . "AcDbEntity")
                            (cons 8 spachk:*lay-text*)
                            '(100 . "AcDbBlockReference")
                            '(66 . 1)          ; attributes follow
                            (cons 2 spachk:*details-block*)
                            (cons 10 p)))))
  (foreach tag (list (list "GRADE" (strcat "GRADE: " grade) 12.0)
                     (list "TAPER" (strcat "TAPER: " taper) 0.0))
    (spachk:demo-ent
      (entmakex (list '(0 . "ATTRIB") '(100 . "AcDbEntity")
                      (cons 8 spachk:*lay-text*) '(100 . "AcDbText")
                      (list 10 (car p) (+ (cadr p) (caddr tag)) 0.0)
                      '(40 . 5.0) (cons 1 (cadr tag))
                      '(100 . "AcDbAttribute") (cons 2 (car tag))
                      '(70 . 0)))))
  (spachk:demo-ent
    (entmakex (list '(0 . "SEQEND") '(100 . "AcDbEntity")
                    (cons 8 spachk:*lay-text*))))
  e)

;; Pause with an explanation, zoomed on what is being explained.
(defun spachk:demo-say (n of ent title lines / l)
  (if ent (spachk:zoom-ent ent))
  (princ (strcat "\n\n--- " (itoa n) " of " (itoa of) ": " title " ---"))
  (foreach l lines (princ (strcat "\n  " l)))
  ((lambda (v) (if lzd:ask (lzd:ask "\n  (Enter to go on) " v) v))
    (getstring "\n  (Enter to go on) ")))

(defun spachk:demo (/ base x y e cov wat lay rmark nx stuck)
  (setq spachk:*demo-ents* nil)
  (foreach lay (list (list spachk:*lay-cover* 3)
                     (list spachk:*lay-water* 5)
                     (list spachk:*lay-dim* 7)
                     (list spachk:*lay-text* 7)
                     (list spachk:*border-layer* 8))
    (spachk:ensure-layer (car lay) (cadr lay)))
  (setq base (getpoint "\nPick an empty spot for the practice drawing: "))
  (if lzd:ask (lzd:ask "\nPick an empty spot for the practice drawing: " base) base)
  (if (null base)
    (princ "\nNo spot picked - demo skipped.")
    (progn
      ;; the pick is a UCS point; the demo is built in WORLD numbers
      ;; (entmake takes nothing else) and each dim point goes back to the
      ;; UCS for its command in spachk:demo-dim
      (setq base (trans base 1 0)
            x    (car base)
            y    (cadr base))
      (spachk:dimstysave)
      ;; only when undo is recording - _Begin in a drawing with UNDO
      ;; off (bit 1 of UNDOCTL clear) errors out of the command
      ;; undo-open is c:TUTORIALSPACHECK's LOCAL, set here through
      ;; dynamic scope: the tutorial's handler is the one that closes
      ;; the group when an Esc lands on a pause inside it, and a local
      ;; of that run cannot survive into the next the way the global
      ;; spachk:*undo-open* did
      (if (= 1 (logand 1 (getvar "UNDOCTL")))
        (progn
          (command "_.UNDO" "_Begin")
          (setq undo-open T)))
      ;; the cover, and a water's edge 3 in from it
      (setq cov (spachk:demo-rect (list x y) 84.0 60.0 spachk:*lay-cover*)
            wat (spachk:demo-rect (list (+ x 3.0) (+ y 3.0))
                                  78.0 54.0 spachk:*lay-water*))
      ;; overall dims, cover noted -- the top one deliberately WRONG:
      ;; it reads 80 across a cover that is really 84
      (spachk:demo-dim (list x (+ y 60.0)) (list (+ x 80.0) (+ y 60.0))
                       (list (+ x 40.0) (+ y 84.0))
                       (strcat "\\X" spachk:*sfx-cover*) spachk:*ds-cover*)
      (spachk:demo-dim (list x y) (list x (+ y 60.0))
                       (list (- x 36.0) (+ y 30.0))
                       (strcat "\\X" spachk:*sfx-cover*) spachk:*ds-cover*)
      ;; the water's edge overalls and the overlap between the two, so
      ;; the only things the scan reports are the three planted faults
      (spachk:demo-dim (list (+ x 3.0) (+ y 3.0)) (list (+ x 81.0) (+ y 3.0))
                       (list (+ x 42.0) (+ y 21.0))
                       (strcat "\\X" spachk:*sfx-water*) spachk:*ds-water*)
      (spachk:demo-dim (list (+ x 3.0) (+ y 3.0)) (list (+ x 3.0) (+ y 57.0))
                       (list (+ x 21.0) (+ y 30.0))
                       (strcat "\\X" spachk:*sfx-water*) spachk:*ds-water*)
      (spachk:demo-dim (list x y) (list (+ x 3.0) y)
                       (list (+ x 1.5) (- y 12.0))
                       (strcat "\\X" spachk:*sfx-lap*) spachk:*ds-cover*)
      ;; a hinge with NO label -- the second planted fault
      (spachk:demo-line (list (+ x 42.0) y) (list (+ x 42.0) (+ y 60.0))
                        spachk:*lay-cover*)
      ;; the details block, so the hinge section has a taper to work
      ;; from and can get as far as noticing the missing label
      (spachk:demo-block (list (+ x 120.0) (+ y 40.0)) "STANDARD" "4-3")
      ;; a border at the LINER size instead of 0.6x it -- the third
      (spachk:demo-rect (list (- x 200.0) (- y 200.0))
                        spachk:*liner-w* spachk:*liner-h*
                        spachk:*border-layer*)
      (command "_.ZOOM" "_Extents")
      (princ (strcat "\n\nA practice spa, with three faults planted in it."
                     "\nSPACHECK finds each one without being told where."))
      (spachk:demo-say
        1 3 cov "the overall that disagrees with the outline"
        (list "The cover polyline measures 84 x 60."
              "The dimension across the top says 80."
              ""
              "SPACHECK measures the outline itself and compares every"
              (strcat "dimension noted '" spachk:*sfx-cover*
                      "' against it, so a dim typed over,")
              "stretched, or left behind after a resize is named with"
              "both numbers - what it reads and what the cover is."))
      (spachk:demo-say
        2 3 nil "the hinge with no label"
        (list "One hinge line runs down the middle of the cover."
              (strcat "There is no MTEXT on the " spachk:*lay-text*
                      " layer against it.")
              ""
              "Every hinge must say whether it is a fold hinge or a"
              "velcro one, because the Hinge Arrangement Chart is read"
              "off those labels.  An unlabelled hinge is reported by"
              "number, and the arrangement check cannot run without it."))
      (spachk:demo-say
        3 3 nil "the title block left at the liner size"
        (list (strcat "The border is " (rtos spachk:*liner-w*) " x "
                      (rtos spachk:*liner-h*) " - the LINER block size.")
              (strcat "A spa title block must be exactly "
                      (rtos spachk:*title-frac* 2 2) "x that: "
                      (rtos (* spachk:*title-frac* spachk:*liner-w*)) " x "
                      (rtos (* spachk:*title-frac* spachk:*liner-h*)) ".")
              ""
              "This is the easiest one to get wrong, because a border"
              "copied from a liner sheet looks right until it plots."
              "SPACHECK names the factor it actually came out at."))
      (if undo-open
        (progn (command "_.UNDO" "_End")
               (setq undo-open nil)))
      (spachk:dimstyrestore)
      (if (= "Yes" (spachk:askkw "Run SPACHECKSCAN on it now"
                                 "Yes No" nil "Yes" nil))
        (progn
          ;; the real command, not a rehearsal of it -- so it asks for a
          ;; selection exactly as it always does.  And it has a handler of
          ;; its own: an Esc inside it runs THAT one and unwinds straight
          ;; to the command line, past TUTORIALSPACHECK's, which left the
          ;; drafter on the dimension layer with CMDECHO off.  So the
          ;; tutorial's oldlay and oldecho -- seen here by dynamic scope,
          ;; like undo-open above -- go back BEFORE the hand-off.  The
          ;; group and the dim style are already closed.
          (if oldlay (setvar "CLAYER" oldlay))
          (if oldecho (setvar "CMDECHO" oldecho))
          (princ (strcat "\n(SPACHECKSCAN asks what to scan - press Enter"
                         " to take the whole drawing.)"))
          ;; the last entity before the scan: what the scan writes on
          ;; the report layer follows it, and nothing else does
          (setq rmark (entlast))
          (c:SPACHECKSCAN)))
      ;; Enter keeps the practice drawing; only an explicit Yes erases it
      (if (= "Yes" (spachk:askkw "Erase the practice drawing?"
                                 "Yes No" nil "No" nil))
        (progn
          ;; an erase that is refused (a locked layer) is counted, so
          ;; the line at the end never says "erased" over objects that
          ;; are still on screen.  The details block's ATTRIBs and SEQEND
          ;; are not asked: entdel takes only a main entity, and they
          ;; go with the INSERT they belong to
          (setq stuck 0)
          (foreach e spachk:*demo-ents*
            (if (and (entget e)
                     (not (member (spachk:etype e) '("ATTRIB" "SEQEND"))))
              (if (not (entdel e)) (setq stuck (1+ stuck)))))
          ;; ...and the report the practice scan wrote, and nothing
          ;; older: the report layer is where EVERY scan in the drawing
          ;; writes, and sweeping it whole took the drafter's own
          ;; reports down with the practice one.  What this run added
          ;; is what follows RMARK; with no scan run there is none
          (if rmark
            (progn
              (setq e (entnext rmark))
              (while e
                (setq nx (entnext e))
                (if (= (strcase (cdr (assoc 8 (entget e))))
                       (strcase spachk:*report-layer*))
                  (if (not (entdel e)) (setq stuck (1+ stuck))))
                (setq e nx))))
          (if (= stuck 0)
            (princ "\nPractice drawing erased.")
            (princ (strcat "\n" (itoa stuck)
                           " object(s) of the practice run on a locked layer NOT erased"
                           " - unlock the layer and erase them by hand.")))))
      (setq spachk:*demo-ents* nil)))
  (princ))

(defun c:TUTORIALSPACHECK ( / *error* undo-open oldecho oldlay ans l)
  (defun *error* (msg)
    ;; the demo's undo group and dim style are the tutorial's to close:
    ;; its pauses sit INSIDE the group, so an Esc at one used to leave
    ;; it open and the user's next U swallowed their own work
    (if undo-open
      (progn (vl-catch-all-apply 'command-s (list "_.UNDO" "_End"))
             (setq undo-open nil)))
    (spachk:dimstyrestore)
    (if oldecho (setvar "CMDECHO" oldecho))
    (if oldlay (setvar "CLAYER" oldlay))
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nTUTORIALSPACHECK error: " msg)))
    (if lzd:report (lzd:report "TUTORIALSPACHECK" *spacheck-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "TUTORIALSPACHECK" *spacheck-version*))
  (setq oldecho (getvar "CMDECHO") oldlay (getvar "CLAYER"))
  (setvar "CMDECHO" 0)
  (setq ans (spachk:askkw "Show me" "Checks Demo Both" nil "Both" nil))
  (if (member ans '("Checks" "Both"))
    (foreach l (spachk:tut-checklist) (princ (strcat "\n" l))))
  (if (member ans '("Demo" "Both"))
    (spachk:demo))
  (setvar "CLAYER" oldlay)
  (setvar "CMDECHO" oldecho)
  (if lzd:end (lzd:end "TUTORIALSPACHECK"))
  (princ))

;; -------------------- self tests ---------------------------------------
;; What LAZDIAG runs on the drafter's machine after this tool fails, and
;; writes into the report: the tool's own helpers on inputs whose answers
;; are KNOWN, so the report says whether the arithmetic was sound where
;; it ran.  (label expression expected) passes when the value is equal
;; to expected (to 1e-6); (label expression) passes when it is not nil,
;; and the value is written down either way.  Nothing here may prompt,
;; draw or (command): it is evaluated from inside *error*.
;; tests/test_selftests.py runs every entry in the VM at both tiers.
(defun spachk:selftests ()
  (list
    (list "has finds a substring and reads a nil text as no match"
          '(if (spachk:has nil "Size") nil (spachk:has "Cover Size" "Size"))  T)
    (list "tapernorm reads a labelled taper by its vocabulary"
          '(spachk:tapernorm "Taper: 4-2 Flat")  "4-2")
    (list "gradenorm reads FRP as Ultra"
          '(spachk:gradenorm "Ultra FRP")  "ULTRA")
    (list "fr-fold lifts -80 degrees to 10"
          '(spachk:fr-fold (/ (* -80.0 pi) 180.0))  (/ pi 18.0))
    (list "fr-adiff: 10 and 80 degrees are 20 apart, a quarter turn being none"
          '(spachk:fr-adiff (/ pi 18.0) (/ (* 4.0 pi) 9.0))  (/ pi 9.0))
    (list "fr-mode: a quarter turn is the same direction"
          '(spachk:fr-mode (list (cons 0.0 10.0) (cons (* 0.5 pi) 5.0)))  0.0)
    (list "hardverdict with no hinge length says so instead of guessing"
          '(cdr (spachk:hardverdict '(OVER 120.0) nil))
          "no hinge length to check - verify by hand")
    (list "foampick takes the first sheet both the width and the run fit"
          '(spachk:foampick (list (cons 48.0 96.0) (cons 49.5 102.0)) 48.0 90.0)
          '(48.0 . 96.0))
    (list "clusters: two boxes a hair apart are one sheet, a far one is another"
          '(length (spachk:clusters '(((0.0 0.0) (10.0 10.0))
                                      ((10.001 0.0) (20.0 10.0))
                                      ((100.0 100.0) (110.0 110.0)))
                                    0.5))
          2)
    (list "date-verdict refuses a day the month does not have"
          '(spachk:date-verdict "02/30/2024")
          "'02/30/2024' - 30 is not a valid day for that month - expected MM/DD/YYYY")
    (list "feet-open-p: 5'-6\" is closed, 15' 6 is not"
          '(if (spachk:feet-open-p "5'-6\"") nil (spachk:feet-open-p "15' 6"))  T)
    (list "ftin spells 66.5 as 5'-6 1/2\" at sixteenths"
          '(spachk:ftin 66.5 4 4)  "5'-6 1/2\"")))

(foreach c '("SPACHECK" "SPACHECKRESCUE" "TUTORIALSPACHECK")
  (setq *calofin-selftests*
        (cons (cons c 'spachk:selftests) *calofin-selftests*)))

;; Quiet inside the whole build: LAZPASS.lsp and
;; CALOFIN-LOADER.lsp set the flag while they load their members,
;; because one file's greeting is a greeting and sixty-three of
;; them is a wall the drafter scrolls past in every drawing they
;; open.  APPLOADed alone the flag is nil and this prints, which
;; is the one time somebody wants to be told.  CALVER reports the
;; whole roster whenever it is asked.
(if (not *calofin-quiet*)
  (princ (strcat "\nSPACHECK " *spacheck-version*
                 " loaded.  Type SPACHECK to run.")))
(princ)
