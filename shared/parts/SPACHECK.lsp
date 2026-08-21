;;; ======================================================================
;;; SPACHECK.lsp  --  audit a finished spa drawing against what SPA draws
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  SPACHECK        guided review of everything it flags
;;;            SPACHECKSCAN    the same audits, read-only
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
;;;   4. THE DIMENSIONS.  Every one is checked for
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
;;;   6. THE TITLE BLOCK.  Everything on the border layer is measured
;;;      together, so a frame drawn as one polyline and one drawn as
;;;      four lines both measure the same.  A spa sheet's title block is
;;;      exactly 0.6x the liner block: the liner nominal is 704 x
;;;      543.625, so the spa nominal is 422.4 x 326.175.  Anything else
;;;      is reported with the factor it actually came out at, and a
;;;      border out of proportion is reported separately as STRETCHED.
;;;
;;;   7. A SPACHECK REPORT (MTEXT) is placed to the RIGHT of the
;;;      drawing, sized to scale with it.  Problems in RED at full
;;;      size, advice in CYAN, all-clear in green at 75%.
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

(setq *spacheck-version* "v1.0")

;; vlax-* is used for bounding boxes, so load Visual LISP once here
;; rather than inside a command body.
(vl-load-com)

;;; -------------------- tunables ----------------------------------------

;; Layers SPA draws on -- the audit is only as right as these are.
(setq spachk:*lay-cover*  "COVER")      ; the cover outline and the hinges
(setq spachk:*lay-water*  "POOL")       ; the water's edge outline
(setq spachk:*lay-dim*    "DIMENSION")  ; every dimension
(setq spachk:*lay-text*   "TEXT")       ; the hinge labels
(setq spachk:*lay-notes*  "SPA-NOTES")  ; corner letters, mode note, report

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

;; Marking and report.
(setq spachk:*sysold*      nil)      ; saved sysvars, restored on the way out
(setq spachk:*demo-ents*   nil)      ; what TUTORIALSPACHECK's demo drew
(setq spachk:*grey-color*  8)
(setq spachk:*flag-color*  1)        ; red: what you confirmed is wrong
(setq spachk:*report-layer* "SPACHECK-REPORT")
(setq spachk:*report-color* 3)
(setq spachk:*green-scale* 0.75)     ; all-clear text height vs the red
(setq spachk:*advice-color* 4)       ; cyan: advice, not a failure
(setq spachk:*report-chars* 48.0)    ; report column width, in text heights
(setq spachk:*zoom-margin* 0.75)

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

;;; -------------------- small helpers -----------------------------------

(defun spachk:join (lst sep / out s)
  (foreach s lst
    (setq out (if out (strcat out sep s) s)))
  (if out out ""))

;; Everything after the last colon, trimmed: "Taper: 4-2" -> "4-2".
(defun spachk:aftercolon (s / i out)
  (setq i (strlen s) out s)
  (while (> i 0)
    (if (= ":" (substr s i 1))
        (progn (setq out (substr s (1+ i))) (setq i 0))
        (setq i (1- i))))
  (cal:trim out))

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
;;;  problem, 2 = advice.  The three render differently in the MTEXT.

;; A report row is (text . level): nil = all clear, 1 = a problem,
;; 2 = advice.  spachk:lvl-p compares nil-safely -- (= nil 1) is not
;; something to rely on.
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

(defun spachk:render (r)
  (cond ((spachk:lvl-p r 1) (spachk:red (spachk:row-txt r)))
        ((spachk:lvl-p r 2) (spachk:cyan (spachk:row-txt r)))
        (t (spachk:small (spachk:row-txt r)))))

;;; -------------------- layers ------------------------------------------
;;;  The canonical ensure-layer: create, or when it already exists make
;;;  sure it is on, thawed and unlocked -- without this a successful run
;;;  onto a frozen layer looks like the command did nothing.

;;; -------------------- entity helpers ----------------------------------

(defun spachk:dxf (code ent) (cdr (assoc code (entget ent))))

(defun spachk:etype (ent) (spachk:dxf 0 ent))

(defun spachk:layer (ent) (spachk:dxf 8 ent))

(defun spachk:on-layer-p (ent name)
  (= (strcase (spachk:layer ent)) (strcase name)))

;; Overall extents of a list of entities: ((minx miny) (maxx maxy)).
(defun spachk:bbox-of (ents / e bb lo hi)
  (foreach e ents
    (if (setq bb (cal:bbox-ent e))
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

(defun spachk:closed-p (ent / f)
  (cond ((member (spachk:etype ent) '("CIRCLE" "ELLIPSE")) t)
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
               (member (spachk:etype e)
                       '("LWPOLYLINE" "POLYLINE" "CIRCLE" "ELLIPSE")))
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
               (member (spachk:etype e) '("LINE" "ARC")))
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

(defun spachk:tapernorm (v / u)
  (setq u (strcase v))
  (cond ((spachk:has u "3-2") "3-2")
        ((spachk:has u "4-2") "4-2")
        ((spachk:has u "4-3") "4-3")
        ((spachk:has u "5-3") "5-3")
        ((spachk:has u "5-4") "5-4")
        ((spachk:has u "3-3") "3-3")
        ((spachk:has u "3/8") "1-3/8")))

(defun spachk:gradenorm (v / u)
  (setq u (strcase (if v v "")))
  (cond ((spachk:has u "ECON") "ECONOMY")
        ((or (spachk:has u "ULTRA") (spachk:has u "FRP")) "ULTRA")
        ((spachk:has u "THERMO") "THERMOLIGHT")
        (t "STANDARD")))

(defun spachk:gradeshort (g)
  (cond ((= g "ECONOMY") "ECO") ((= g "STANDARD") "STD")
        ((= g "ULTRA") "ULTRA") (t "THERMO")))

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
  (and f (numberp f) (member (logand 7 f) '(0 1))))

;; The dimension line's own location (DXF 10).
(defun spachk:dim-loc (ent) (spachk:dxf 10 ent))

;; Every dimension in the selection, whatever layer it sits on.
(defun spachk:dims (ss) (spachk:ents-of-type ss "DIMENSION"))

;; The dimensions whose text carries a given note.
(defun spachk:dims-noted (dims note / e out)
  (foreach e dims
    (if (spachk:has (spachk:dim-text e) note) (setq out (cons e out))))
  (reverse out))

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
(defun spachk:title-verdict (bb / bw bh tw th sw sh sc)
  (setq tw (* spachk:*title-frac* spachk:*liner-w*)
        th (* spachk:*title-frac* spachk:*liner-h*))
  (if (null bb)
    (strcat "NO BORDER found on layer '" spachk:*border-layer* "'")
    (progn
      (setq bw (spachk:bw bb) bh (spachk:bh bb))
      (if (or (<= bw 1.0e-6) (<= bh 1.0e-6))
        "border has no measurable size"
        (progn
          (setq sw (/ bw tw) sh (/ bh th) sc (min sw sh))
          (cond
            ;; out of proportion is wrong whatever its size
            ((> (abs (- sw sh)) (* spachk:*border-tol* (max sw sh)))
             (strcat (rtos bw) " x " (rtos bh)
                     " - STRETCHED out of proportion (" (rtos sw 2 3)
                     "x wide but " (rtos sh 2 3) "x tall); a spa title"
                     " block is " (rtos tw) " x " (rtos th)))
            ;; the size the user asked for by name
            ((and (> sc (- 1.0 spachk:*border-tol*))
                  (< sc (+ 1.0 spachk:*border-tol*)))
             (strcat (rtos bw) " x " (rtos bh) " - "
                     (rtos spachk:*title-frac* 2 2)
                     "x the liner block, OK"))
            (t
             (strcat (rtos bw) " x " (rtos bh) " is "
                     (rtos (* sc spachk:*title-frac*) 2 3)
                     "x the liner block "
                     (rtos spachk:*liner-w*) " x " (rtos spachk:*liner-h*)
                     " - a spa title block must be exactly "
                     (rtos spachk:*title-frac* 2 2) "x it ("
                     (rtos tw) " x " (rtos th) ")"))))))))

;; Everything on the border layer, from the selection when it holds the
;; border and from the whole drawing when it does not.
(defun spachk:border-box (ss / ents ss2 i e out)
  (setq ents nil i 0)
  (if ss
    (repeat (sslength ss)
      (setq e (ssname ss i) i (1+ i))
      (if (and (entget e) (spachk:on-layer-p e spachk:*border-layer*))
        (setq ents (cons e ents)))))
  (if (null ents)
    (progn
      (setq ss2 (ssget "_X" (list (cons 8 spachk:*border-layer*))) i 0)
      (if ss2
        (repeat (sslength ss2)
          (setq e (ssname ss2 i) i (1+ i) ents (cons e ents))))))
  (if ents (spachk:bbox-of ents)))

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
                            (strcat "Spa Cover Details: Thermo-Light is"
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

(defun spachk:audit-nesting (cov wat / rows bc bw)
  (setq rows nil)
  (if (and cov wat)
    (progn
      (setq bc (cal:bbox-ent cov) bw (cal:bbox-ent wat))
      (if (and bc bw)
        (if (spachk:inside-p bw bc 1.0e-6)
          (setq rows (list (spachk:row
                             (strcat "Cover vs water's edge: cover "
                                     (rtos (spachk:bw bc)) " x "
                                     (rtos (spachk:bh bc))
                                     " contains water's edge "
                                     (rtos (spachk:bw bw)) " x "
                                     (rtos (spachk:bh bw)) ", OK")
                             nil)))
          (setq rows (list (spachk:row
                             (strcat "Cover vs water's edge: the water's"
                                     " edge is NOT INSIDE the cover"
                                     " - the cover is always the larger"
                                     " of the two")
                             1)))))))
  (spachk:res rows nil))

;;; --- 4. the dimensions --------------------------------------------------

;; Every dimension: right layer, right style, and does its measurement
;; agree with the distance between its own definition points?
(defun spachk:audit-dims (dims covdim watdim / rows ents e m d p1 p2 sty want)
  (setq rows nil ents nil)
  (foreach e dims
    ;; layer
    (if (not (spachk:on-layer-p e spachk:*lay-dim*))
      (setq rows (append rows
                  (list (spachk:row
                          (strcat "Dim " (spachk:dxf 5 e) ": on layer "
                                  (spachk:layer e) ", should be "
                                  spachk:*lay-dim*)
                          1)))
            ents (cons e ents)))
    ;; style: a Water's Edge dim takes the 0.5 style, everything else
    ;; the cover style
    (setq want (if (spachk:has (spachk:dim-text e) spachk:*sfx-water*)
                   spachk:*ds-water* spachk:*ds-cover*)
          sty  (spachk:dim-style e))
    (if (and (/= sty "") (/= (strcase sty) (strcase want)))
      (setq rows (append rows
                  (list (spachk:row
                          (strcat "Dim " (spachk:dxf 5 e) ": style '"
                                  sty "', should be '" want "'")
                          1)))
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
              (setq rows (append rows
                          (list (spachk:row
                                  (strcat "Dim " (spachk:dxf 5 e)
                                          ": reads " (rtos m)
                                          " but spans " (rtos d)
                                          " - the dimension DISAGREES"
                                          " with its own points")
                                  1)))
                    ents (cons e ents))))))))
  (spachk:res rows (reverse ents)))

;; The roster: are the dimensions a finished spa sheet needs present,
;; and do the overalls read the outline's true size?
(defun spachk:audit-roster (dims cov wat / rows ents covn watn lapn bb
                                           m want e)
  (setq rows nil ents nil
        covn (spachk:dims-noted dims spachk:*sfx-cover*)
        watn (spachk:dims-noted dims spachk:*sfx-water*)
        lapn (spachk:dims-noted dims spachk:*sfx-lap*))
  ;; --- the cover's overalls
  (setq bb (if cov (cal:bbox-ent cov) nil))
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
     (if bb
       (foreach e covn
         (setq m (spachk:dim-meas e))
         (if m
           (if (and (> (abs (- m (spachk:bw bb))) spachk:*meas-tol*)
                    (> (abs (- m (spachk:bh bb))) spachk:*meas-tol*))
             (setq rows (append rows
                         (list (spachk:row
                                 (strcat "Overall " (spachk:dxf 5 e)
                                         ": reads " (rtos m)
                                         " but the cover measures "
                                         (rtos (spachk:bw bb)) " x "
                                         (rtos (spachk:bh bb)))
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
        (setq m (spachk:dim-meas (car lapn))
              want (if (and (cal:bbox-ent cov) (cal:bbox-ent wat))
                       (* 0.5 (- (spachk:bw (cal:bbox-ent cov))
                                 (spachk:bw (cal:bbox-ent wat))))
                       nil))
        (if (and m want (> (abs (- m want)) spachk:*meas-tol*))
          (setq rows (append rows
                      (list (spachk:row
                              (strcat "Overlap: reads " (rtos m)
                                      " but the cover laps the water's"
                                      " edge by " (rtos want))
                              1)))
                ents (cons (car lapn) ents))
          (setq rows (append rows
                      (list (spachk:row
                              (strcat "Overlap: " (rtos m) ", OK")
                              nil))))))))
  (spachk:res rows (reverse ents)))

;; The overalls' standoffs -- SPA puts the across dim 2 ft above the
;; cover and the up dim 3 ft to its left.
(defun spachk:audit-standoff (covn cov / rows bb e loc dx dy)
  (setq rows nil)
  (if (and cov covn (setq bb (cal:bbox-ent cov)))
    (foreach e covn
      (setq loc (spachk:dim-loc e))
      (if loc
        (progn
          (setq dy (- (cadr loc) (cadadr bb))     ; above the top
                dx (- (caar bb) (car loc)))       ; left of the left edge
          (cond
            ;; above the cover: the across dim
            ((> dy 0.0)
             (if (> (abs (- dy spachk:*topoff*)) spachk:*off-tol*)
               (setq rows (append rows
                           (list (spachk:row
                                   (strcat "Overall " (spachk:dxf 5 e)
                                           ": stands " (rtos dy)
                                           " above the cover, SPA puts it "
                                           (rtos spachk:*topoff*))
                                   1))))))
            ;; left of the cover: the up dim
            ((> dx 0.0)
             (if (> (abs (- dx spachk:*dimoff*)) spachk:*off-tol*)
               (setq rows (append rows
                           (list (spachk:row
                                   (strcat "Overall " (spachk:dxf 5 e)
                                           ": stands " (rtos dx)
                                           " left of the cover, SPA puts it "
                                           (rtos spachk:*dimoff*))
                                   1)))))))))))
  (spachk:res rows nil))

;;; --- 5. the hinges ------------------------------------------------------

;; A hinge's label: the MTEXT on the TEXT layer nearest its line.
(defun spachk:hinge-label (hng labels / best bestd p q d e bb)
  (setq bb (cal:bbox-ent hng))
  (if bb
    (progn
      (setq p (list (* 0.5 (+ (caar bb) (caadr bb)))
                    (* 0.5 (+ (cadar bb) (cadadr bb)))))
      (foreach e labels
        (setq q (spachk:dxf 10 e)
              d (distance (list (car p) (cadr p)) (list (car q) (cadr q))))
        (if (or (null bestd) (< d bestd)) (setq bestd d best e)))))
  (if best (spachk:dxf 1 best)))

(defun spachk:audit-hinges (ss cov grade taper / rows ents hngs labels n xs
                                                 row opts allowed fw fl
                                                 sorted e bb want got
                                                 maxrun maxpiece prev
                                                 allvel hw h r k nm vd lvl)
  (setq rows nil ents nil
        hngs (vl-remove-if-not
               '(lambda (e) (= (spachk:etype e) "LINE"))
               (spachk:loose-ents ss spachk:*lay-cover*))
        labels (vl-remove-if-not
                 '(lambda (e) (spachk:on-layer-p e spachk:*lay-text*))
                 (spachk:ents-of-type ss "MTEXT")))
  (if (null hngs)
    (spachk:res
      (list (spachk:row "Hinges: none drawn on layer COVER" 1)) nil)
    (progn
      ;; west to east
      (setq sorted (vl-sort hngs
                     '(lambda (a b)
                        (< (car (spachk:dxf 10 a)) (car (spachk:dxf 10 b))))))
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
      (setq fw (car (car opts)) fl (cdr (car opts)))
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
                          (abs (- (cadr (spachk:dxf 11 e))
                                  (cadr (spachk:dxf 10 e)))))))
      (if (and fl (> maxrun (+ fl 0.01)))
        (setq rows (append rows
                    (list (spachk:row
                            (strcat "Foam length: longest hinge "
                                    (rtos maxrun) " exceeds the "
                                    (rtos fl) " sheet")
                            1))))
        (setq rows (append rows
                    (list (spachk:row
                            (strcat "Foam length: longest hinge "
                                    (rtos maxrun)
                                    (if fl
                                        (strcat " within " (rtos fl) ", OK")
                                        (strcat " - Thermo-Light length"
                                                " N/A, verify")))
                            (if fl nil 2))))))
      ;; --- piece widths against the foam width.  This one DOES need
      ;;     the cover: a piece is bounded by the outline's edges.
      (if (and cov (setq bb (cal:bbox-ent cov)))
        (progn
          (setq maxpiece 0.0 prev (caar bb))
          (foreach e sorted
            (setq maxpiece (max maxpiece (- (car (spachk:dxf 10 e)) prev))
                  prev (car (spachk:dxf 10 e))))
          (setq maxpiece (max maxpiece (- (caadr bb) prev)))
          (if (> maxpiece (+ fw 0.01))
            (setq rows (append rows
                        (list (spachk:row
                                (strcat "Foam width: widest piece "
                                        (rtos maxpiece) " exceeds the "
                                        (rtos fw) " sheet")
                                1))))
            (setq rows (append rows
                        (list (spachk:row
                                (strcat "Foam width: widest piece "
                                        (rtos maxpiece) " within "
                                        (rtos fw) ", OK")
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
                                           "Velcro")
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

(defun spachk:audit-title (ss / bb s)
  (setq bb (spachk:border-box ss)
        s  (spachk:title-verdict bb))
  (spachk:res
    (list (spachk:row (strcat "Title block: " s)
                      (if (spachk:has s "OK") nil 1)))
    nil))

;;; ======================================================================
;;;  RUNNING THE AUDIT
;;; ======================================================================

;; Everything, in report order.  Returns (rows . flagged-entities).
(defun spachk:audit (ss / rows ents blk att g tp cov wat covo wato
                          dims covn r)
  (setq rows nil ents nil)

  ;; 1 -- the block
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
  (setq r (spachk:audit-outline ss spachk:*lay-cover* "Cover outline" t)
        rows (append rows (spachk:res-rows r))
        ents (append ents (spachk:res-ents r))
        covo (spachk:outline-ents ss spachk:*lay-cover*)
        cov  (if (= 1 (length covo)) (car covo) nil))

  ;; 3 -- the water's edge outline
  (setq r (spachk:audit-outline ss spachk:*lay-water* "Water's edge" nil)
        rows (append rows (spachk:res-rows r))
        ents (append ents (spachk:res-ents r))
        wato (spachk:outline-ents ss spachk:*lay-water*)
        wat  (if (= 1 (length wato)) (car wato) nil))

  (setq r (spachk:audit-nesting cov wat)
        rows (append rows (spachk:res-rows r)))

  ;; 4 -- the dimensions
  (setq dims (spachk:dims ss)
        r    (spachk:audit-dims dims cov wat)
        rows (append rows (spachk:res-rows r))
        ents (append ents (spachk:res-ents r)))
  (setq r (spachk:audit-roster dims cov wat)
        rows (append rows (spachk:res-rows r))
        ents (append ents (spachk:res-ents r)))
  (setq covn (spachk:dims-noted dims spachk:*sfx-cover*)
        r    (spachk:audit-standoff covn cov)
        rows (append rows (spachk:res-rows r)))

  ;; 5 -- the hinges (only meaningful with a taper)
  (if tp
    (progn
      (setq r (spachk:audit-hinges ss cov g tp)
            rows (append rows (spachk:res-rows r))
            ents (append ents (spachk:res-ents r))))
    (setq rows (append rows
                (list (spachk:row
                        "Hinges: not checked - no taper to check against"
                        1)))))

  ;; 6 -- the title block
  (setq r (spachk:audit-title ss)
        rows (append rows (spachk:res-rows r)))

  (cons rows ents))

;;; -------------------- the report --------------------------------------

(defun spachk:write-report (rows bb readonly / nlin ref h ins txt r nbad nadv)
  (cal:ensure-layer spachk:*report-layer* spachk:*report-color*)
  (setq nbad 0 nadv 0)
  (foreach r rows
    (cond ((spachk:lvl-p r 1) (setq nbad (1+ nbad)))
          ((spachk:lvl-p r 2) (setq nadv (1+ nadv)))))
  ;; height: scale the sheet to the drawing, as the siblings do
  (setq nlin 4.0)
  (foreach r rows
    (setq nlin (+ nlin (if (spachk:row-lvl r) 1.0 spachk:*green-scale*))))
  (if (and bb (> (max (spachk:bw bb) (spachk:bh bb)) 1.0e-8))
    (progn
      (setq ref (max (spachk:bh bb) (* 0.25 (spachk:bw bb)))
            h   (/ ref (* 1.66 nlin)))
      (if (> h (/ ref 30.0))  (setq h (/ ref 30.0)))
      (if (< h (/ ref 200.0)) (setq h (/ ref 200.0))))
    (setq h 2.5))
  (setq ins (if bb
                (list (+ (caadr bb) (* 0.05 (max (spachk:bw bb) 1.0)))
                      (cadadr bb) 0.0)
                (list 0.0 0.0 0.0)))
  (setq txt (strcat (if readonly "SPACHECKSCAN REPORT - " "SPACHECK REPORT - ")
                    (cal:datestr)
                    "  [SPACHECK " *spacheck-version* "]"
                    "\\P"
                    (spachk:small
                      (strcat (if readonly
                                  "Read-only scan - nothing in the drawing was changed.  "
                                  "")
                              "Problems in " (spachk:red "red")
                              ", advice in " (spachk:cyan "cyan") "."))
                    "\\P"
                    (spachk:small
                      (strcat (itoa nbad) " problem"
                              (if (= 1 nbad) "" "s") ", "
                              (itoa nadv) " advisor"
                              (if (= 1 nadv) "y" "ies")))
                    "\\P"
                    (spachk:small "----------------------------------------")))
  (foreach r rows
    (setq txt (strcat txt "\\P" (spachk:render r))))
  (cal:mtext ins h (* spachk:*report-chars* h) txt spachk:*report-layer*)
  (list nbad nadv))

;;; -------------------- marking (SPACHECK only) -------------------------

(defun spachk:regapp ()
  (if (not (tblsearch "APPID" "SPACHECK")) (regapp "SPACHECK")))

;; Remember the entity's own colour in xdata so SPACHECKRESCUE can put
;; it back even after a crash; an existing stash (from an interrupted
;; run - the TRUE original) is never overwritten.
(defun spachk:stash-color (ent col / ed cur)
  (spachk:regapp)
  (setq ed  (entget ent '("SPACHECK"))
        cur (cdr (assoc 62 (entget ent))))
  (if (and ed (not (assoc -3 ed)))
    (entmod (append ed (list (list -3 (list "SPACHECK"
                                            '(1000 . "COLOR")
                                            (cons 1071 (if cur cur 256))))))))
  ;; now recolour it
  (setq ed (entget ent))
  (entmod (if (assoc 62 ed)
              (subst (cons 62 col) (assoc 62 ed) ed)
              (append ed (list (cons 62 col)))))
  (entupd ent))

;; Put a stashed colour back and drop the xdata.  T when it did.
(defun spachk:unstash (ent / ed xd old)
  (setq ed (entget ent '("SPACHECK"))
        xd (if (assoc -3 ed) (cdadr (assoc -3 ed)) nil))
  (if xd
    (progn
      (setq old (cdr (assoc 1071 xd)))
      (if old
        (progn
          (setq ed (entget ent))
          (entmod (if (= old 256)
                      (if (assoc 62 ed)
                          (vl-remove (assoc 62 ed) ed)
                          ed)
                      (if (assoc 62 ed)
                          (subst (cons 62 old) (assoc 62 ed) ed)
                          (append ed (list (cons 62 old))))))))
      (setq ed (entget ent '("SPACHECK")))
      (entmod (subst (list -3 (list "SPACHECK")) (assoc -3 ed) ed))
      (entupd ent)
      T)))

(defun spachk:zoom-ent (ent / bb p1 p2 m)
  (if (setq bb (cal:bbox-ent ent))
    (progn
      (setq m  (* spachk:*zoom-margin*
                  (max (spachk:bw bb) (spachk:bh bb) 1.0))
            p1 (list (- (caar bb) m) (- (cadar bb) m))
            p2 (list (+ (caadr bb) m) (+ (cadadr bb) m)))
      (command "_.ZOOM" "_Window" p1 p2))))

;;; -------------------- asking ------------------------------------------
;;;  The section-4 helpers, embedded under this file's own prefix.

;;; -------------------- sysvars -----------------------------------------

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

;;; --- SPACHECKSCAN: the audits, read-only -------------------------------

(defun c:SPACHECKSCAN ( / *error* oldecho ss res rows bb ents n)
  (defun *error* (msg)
    (if oldecho (setvar "CMDECHO" oldecho))
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nSPACHECKSCAN error: " msg)))
    (princ))
  (prompt (strcat "\nHighlight the spa drawing and its "
                  spachk:*details-block*
                  " block to SPACHECKSCAN (Enter = whole drawing): "))
  (setq ss (ssget))
  (if (null ss) (setq ss (ssget "_X")))
  (if (null ss)
    (prompt "\nNothing to scan.")
    (progn
      (setq oldecho (getvar "CMDECHO"))
      (setvar "CMDECHO" 0)
      (setq res  (spachk:audit ss)
            rows (car res)
            ents (cdr res)
            bb   (spachk:bbox-of (spachk:outline-ents ss spachk:*lay-cover*))
            n    (spachk:write-report rows bb t))
      (setvar "CMDECHO" oldecho)
      (princ (strcat "\n--- SPACHECKSCAN complete (read-only) ---"
                     "\n" (itoa (car n)) " problem"
                     (if (= 1 (car n)) "" "s") ", "
                     (itoa (cadr n)) " advisor"
                     (if (= 1 (cadr n)) "y" "ies")
                     "\nReport written on layer " spachk:*report-layer*
                     "; nothing else was changed."))))
  (princ))

;;; --- SPACHECK: the audits, then a walk of what they flagged ------------

(defun c:SPACHECK ( / *error* oldecho undo-open ss res rows ents bb n
                      e k tot ans marked)
  (defun *error* (msg)
    (cal:sysrestore)
    (if undo-open (command "_.UNDO" "_End"))
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nSPACHECK error: " msg)))
    (princ))
  (prompt (strcat "\nHighlight the spa drawing and its "
                  spachk:*details-block*
                  " block to SPACHECK (Enter = whole drawing): "))
  (setq ss (ssget))
  (if (null ss) (setq ss (ssget "_X")))
  (if (null ss)
    (prompt "\nNothing to check.")
    (progn
      (cal:syssave '("OSMODE" "CMDECHO" "CLAYER"))
      (setq oldecho (getvar "CMDECHO"))
      (setvar "CMDECHO" 0)
      (command "_.UNDO" "_Begin")
      (setq undo-open T)
      (setq res  (spachk:audit ss)
            rows (car res)
            ents (cdr res)
            bb   (spachk:bbox-of (spachk:outline-ents ss spachk:*lay-cover*)))
      ;; walk what was flagged, one at a time
      (setq tot (length ents) k 0 marked 0)
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
                (setq ans (cal:askkw
                            (strcat "  Item " (itoa k) " of " (itoa tot)
                                    " - mark it as wrong?")
                            "Yes No Skip" "Yes/No/Skip" "No" nil))
                (cond
                  ((= ans "Yes")
                   (spachk:stash-color e spachk:*flag-color*)
                   (setq marked (1+ marked)))
                  ((= ans "Skip") (setq k tot))))))))
      (setq n (spachk:write-report rows bb nil))
      (command "_.ZOOM" "_Extents")
      (command "_.UNDO" "_End")
      (setq undo-open nil)
      (setvar "CMDECHO" oldecho)
      (cal:sysrestore)
      (princ (strcat "\n--- SPACHECK complete ---"
                     "\n" (itoa (car n)) " problem"
                     (if (= 1 (car n)) "" "s") ", "
                     (itoa (cadr n)) " advisor"
                     (if (= 1 (cadr n)) "y" "ies")
                     "\n" (itoa marked) " item"
                     (if (= 1 marked) "" "s") " marked red"
                     "\nReport written on layer " spachk:*report-layer*
                     ".  SPACHECKRESCUE puts the colours back."))))
  (princ))

;;; --- SPACHECKRESCUE: put every colour back -----------------------------

(defun c:SPACHECKRESCUE ( / *error* oldecho ss i e n)
  (defun *error* (msg)
    (if oldecho (setvar "CMDECHO" oldecho))
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nSPACHECKRESCUE error: " msg)))
    (princ))
  (setq oldecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (setq ss (ssget "_X") i 0 n 0)
  (if ss
    (repeat (sslength ss)
      (setq e (ssname ss i) i (1+ i))
      (if (spachk:unstash e) (setq n (1+ n)))))
  ;; and the report itself
  (setq ss (ssget "_X" (list (cons 8 spachk:*report-layer*))) i 0)
  (if ss
    (repeat (sslength ss)
      (entdel (ssname ss i))
      (setq i (1+ i))))
  (setvar "CMDECHO" oldecho)
  (princ (strcat "\nSPACHECKRESCUE: " (itoa n) " colour"
                 (if (= 1 n) "" "s") " put back, report removed."))
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
    "   Thermo-Light must be the 1-3/8 flat taper."
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
            "' measured together.")
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

;; An aligned dim carrying a note, drawn the way SPA draws one.
(defun spachk:demo-dim (p1 p2 at note style / e)
  (spachk:dimstyle-set style)
  (setvar "CLAYER" spachk:*lay-dim*)
  (command "_.DIMALIGNED" p1 p2 "_T" (strcat "<>" note) at)
  (if (setq e (entlast)) (spachk:demo-ent e))
  e)

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
  (getstring "\n  (Enter to go on) "))

(defun spachk:demo (/ base x y e cov wat lay)
  (setq spachk:*demo-ents* nil)
  (foreach lay (list (list spachk:*lay-cover* 3)
                     (list spachk:*lay-water* 5)
                     (list spachk:*lay-dim* 7)
                     (list spachk:*lay-text* 7)
                     (list spachk:*border-layer* 8))
    (cal:ensure-layer (car lay) (cadr lay)))
  (setq base (getpoint "\nPick an empty spot for the practice drawing: "))
  (if (null base)
    (princ "\nNo spot picked - demo skipped.")
    (progn
      (setq x (car base) y (cadr base))
      (command "_.UNDO" "_Begin")
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
      (command "_.UNDO" "_End")
      (if (= "Yes" (cal:askkw "Run SPACHECKSCAN on it now"
                                 "Yes No" "Yes/No" "Yes" nil))
        (progn
          ;; the real command, not a rehearsal of it -- so it asks for a
          ;; selection exactly as it always does
          (princ (strcat "\n(SPACHECKSCAN asks what to scan - press Enter"
                         " to take the whole drawing.)"))
          (c:SPACHECKSCAN)))
      (if (= "Yes" (cal:askkw "Erase the practice drawing"
                                 "Yes No" "Yes/No" "Yes" nil))
        (progn
          (foreach e spachk:*demo-ents* (if (entget e) (entdel e)))
          (setq e (ssget "_X" (list (cons 8 spachk:*report-layer*))))
          (if e
            (progn
              (setq x 0)
              (repeat (sslength e)
                (entdel (ssname e x))
                (setq x (1+ x)))))
          (princ "\nPractice drawing erased.")))
      (setq spachk:*demo-ents* nil)))
  (princ))

(defun c:TUTORIALSPACHECK ( / *error* oldecho oldlay ans l)
  (defun *error* (msg)
    (if oldecho (setvar "CMDECHO" oldecho))
    (if oldlay (setvar "CLAYER" oldlay))
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nTUTORIALSPACHECK error: " msg)))
    (princ))
  (setq oldecho (getvar "CMDECHO") oldlay (getvar "CLAYER"))
  (setvar "CMDECHO" 0)
  (setq ans (cal:askkw "Show me" "Checks Demo Both" "Checks/Demo/Both" "Checks" nil))
  (if (member ans '("Checks" "Both"))
    (foreach l (spachk:tut-checklist) (princ (strcat "\n" l))))
  (if (member ans '("Demo" "Both"))
    (spachk:demo))
  (setvar "CLAYER" oldlay)
  (setvar "CMDECHO" oldecho)
  (princ))

(princ (strcat "\nSPACHECK " *spacheck-version*
               " loaded.  Type SPACHECK to run."))
(princ)
