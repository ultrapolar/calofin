;;; ======================================================================
;;; LOBF.lsp  --  the line of best fit through a set of survey points
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  LOBF     fit a construction line through highlighted points
;;;            LOBFVER  print the loaded version
;;; ======================================================================
;;;
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;
;;;  Highlight points that are all MEANT to be on one straight line -- a
;;;  wall shot at eight stations, a row of deck anchors -- and LOBF draws
;;;  the construction line (an XLINE) that best answers them.
;;;
;;;  THREE FITS, NOT ONE, because "best" is a choice and the choice is
;;;  about WHERE THE ERROR GOES.  All three are drawn at once, each in
;;;  its own colour and numbered on screen, and you keep the one you
;;;  want:
;;;
;;;    1  EVERY POINT.  Least squares on the perpendicular distances:
;;;       the line with the least total error, every point pulling on
;;;       it.  The textbook line of best fit, and the honest answer
;;;       when the points really are all equally good.
;;;
;;;    2  ONE SET ASIDE.  The same fit with a single point left out --
;;;       every point is tried as the one to drop and the drop that
;;;       leaves the REST tightest wins.  The error stops being shared:
;;;       it piles onto one point, which is exactly what you want to
;;;       see when one shot is bad.  The point it gave up on is ringed
;;;       and named, so it can be re-measured instead of quietly
;;;       averaged into the wall.
;;;
;;;    3  TIGHTEST BAND.  The least-MAX fit: the narrowest band that
;;;       still holds every point, centred.  Nobody is further off than
;;;       they have to be, and the number to quote is the half-band.
;;;       (The narrowest band through a point set is always flush with
;;;       an edge of its convex hull, so only those edges are tried.)
;;;
;;;  WHICH ONE ENTER TAKES.  Fit 2 is the default when the point it set
;;;  aside is DRASTICALLY worse than the rest -- lobf:*drastic* times
;;;  the worst of the points it kept, and at least lobf:*drastic-floor*
;;;  off in its own right, so a survey where everything is within a
;;;  sixteenth does not get one of its points called an outlier.  When
;;;  no point stands out that way there is no outlier to isolate and
;;;  fit 1, the balanced one, is the default instead.  The command line
;;;  says which rule fired and by what margin, every run.
;;;
;;;  WHAT IT DRAWS.  While you are choosing: three XLINEs on
;;;  LOBF-PREVIEW, each labelled with its number on a stalk so the
;;;  label cannot be read against the wrong line -- three fits through
;;;  one row of points sit nearly on top of each other, and colour
;;;  alone is not enough to tell them apart.  Fit 2's set-aside point
;;;  is ringed.  When you pick, the losers go: what is left is the
;;;  XLINE you kept, moved onto LOBF and drawn ByLayer, plus that ring
;;;  on LOBF-IGNORED if the fit you kept is one that ignores a point.
;;;
;;;  TWO POINTS make exactly one line, so the picker is skipped and the
;;;  line is simply drawn.  Fewer than two, or every point on the same
;;;  spot, and there is nothing to fit -- it says so rather than
;;;  drawing a line along the X axis and letting you find out later.
;;; ======================================================================

;;; -------------------- version -----------------------------------------
;;;  The banner form tools/release_lisp.py reads (lowercase name, "v",
;;;  one dot).  Bump it with every change and regenerate releases/.

(setq *lobf-version* "v1.0")

;;; ======================================================================
;;;  TUNABLES -- every value LOBF reads that someone might want to
;;;  change lives in this block, and nowhere else in the file.
;;;
;;;  How to change one: edit the value, save, and APPLOAD the file
;;;  again.  To try a value for one session only, type the setq at the
;;;  command line -- e.g. (setq lobf:*drastic* 8.0) -- because every
;;;  knob is read when the command runs, not when the file loads.
;;;
;;;  Units: distances are drawing units (1 unit = 1 inch on the shop's
;;;  sheets); colours are ACI numbers (1 red, 2 yellow, 3 green, 4 cyan,
;;;  5 blue, 6 magenta, 7 white, 8 grey, 256 ByLayer).
;;; ----------------------------------------------------------------------

;; -- where the points are ----------------------------------------------

;; Where the survey points live, and what a point block calls its
;; number -- ABHD's *PF-POINT-LAYER* / *PF-POINT-BLOCK* / *PF-PT-TAG*,
;; the same three ABPCHECK reads.  An ab_pt block counts as a point
;; wherever it sits, so the layer only matters for bare POINT entities
;; and for blocks of some other name.
(setq lobf:*pt-layer* "POINTS")   ; layer holding the survey points
(setq lobf:*pt-block* "ab_pt")    ; block name whose INSERTs mark points
(setq lobf:*pt-tag*   "number")   ; the attribute carrying the number

;; What the highlight is allowed to hand the command.  Only points are
;; wanted -- LOBF fits a line THROUGH points and has nothing to say
;; about lines already drawn -- so a window dragged over the whole
;; sheet picks up the points and leaves the geometry behind rather
;; than making the user pick each one.  A type dropped from here is
;; never seen at all.
(setq lobf:*filter* '((0 . "POINT,INSERT")))

;; Two points closer together than this are one shot, not two: a
;; double-shot must not get two votes in the fit.
(setq lobf:*exact-eps* 1.0e-6)    ; drawing units

;; -- when one point counts as an outlier -------------------------------

;; THE RULE THAT PICKS THE DEFAULT.  Fit 2 sets one point aside; it is
;; offered as the default only when that point is drastically worse
;; than the ones the fit kept -- this many times the worst of them.
;; Lower it and LOBF reaches for the outlier fit more readily; raise it
;; and it wants a more obvious bad shot before it will single one out.
(setq lobf:*drastic*       4.0)   ; multiples of the worst held point

;; ...and at least this far off in its own right.  Without a floor, a
;; survey where every point is within a sixty-fourth would still have a
;; "worst" one four times the rest, and calling that an outlier is
;; reading noise.  Raise it to make LOBF slower to blame a point.
(setq lobf:*drastic-floor* 0.5)   ; drawing units

;; Which fit Enter takes when NO point stands out that way -- there is
;; then no outlier to isolate, so the balanced fit is the answer.  Set
;; it to "3" to have Enter take the tightest band instead.
(setq lobf:*default-fit*   "1")   ; "1", "2" or "3"

;; When fit 1's worst point is further off than this fraction of the
;; run's own length, the points are not really lying along one line and
;; LOBF says so before you pick.  Raise it to quieten the warning.
(setq lobf:*blob-ratio*    0.2)   ; worst error / length of the run

;; -- what it draws -----------------------------------------------------

;; The three layers LOBF writes on, created on first use.  PREVIEW
;; holds the three candidates and their labels and is emptied when you
;; pick; the line you keep moves to LOBF, and the ring round a point a
;; kept fit ignores stays on IGNORED so it can be frozen or erased on
;; its own.  Nothing is ever cleared wholesale: everything LOBF draws
;; carries xdata under the APPID below and only stamped objects are
;; erased again.
(setq lobf:*layer*         "LOBF")           ; the construction line kept
(setq lobf:*color*         4)                ; ACI (cyan)
(setq lobf:*preview-layer* "LOBF-PREVIEW")   ; the three candidates
(setq lobf:*preview-color* 8)                ; ACI (grey) -- each XLINE
                                             ; carries its own colour
(setq lobf:*ign-layer*     "LOBF-IGNORED")   ; ring round a set-aside point
(setq lobf:*ign-color*     1)                ; ACI (red)
(setq lobf:*appid*         "LOBF")           ; renaming this orphans
                                             ; earlier runs

;; The colour each candidate is previewed in, fit 1 first.  These are
;; what the on-screen numbers mean, so the printed table names them.
(setq lobf:*fit-colors*    '(3 2 6))         ; ACI: green, yellow, magenta

;; Label sizing, all as fractions of the run the points cover.  DIV
;; sets the text height (a bigger number is smaller text), GAP is how
;; far past the last point the labels stand, STALK is how far the
;; number sits off its own line -- multiplied by the fit's number, so
;; the three stack instead of overprinting -- and RING is the radius of
;; the circle round a set-aside point, in text heights.
(setq lobf:*label-div*     40.0)
(setq lobf:*label-gap*     0.08)
(setq lobf:*label-stalk*   1.6)   ; text heights, times the fit number
(setq lobf:*ring-scale*    1.2)   ; text heights

;; -- how numbers are printed -------------------------------------------

;; Distances on the command line go through (rtos d mode prec): mode 4
;; is architectural (feet-inches), so 1.875 reads 0'-1 7/8"; prec is
;; how many ways the inch is split, as a power of two.  5 = thirty-
;; seconds, because the errors this tool reports are small ones and
;; sixteenths round too many of them to the same string to compare.
(setq lobf:*dist-mode*     4)     ; rtos mode
(setq lobf:*dist-prec*     5)     ; 2^5 = thirty-seconds of an inch

;; Degrees of bearing printed after each fit, so two fits that read the
;; same to the thirty-second can still be told apart.
(setq lobf:*ang-prec*      2)     ; decimal places

;; Anything smaller than this is zero: the guard on a degenerate fit
;; (every point on one spot), on a zero-length direction, and on the
;; cross products the hull walk turns on.
(setq lobf:*tiny*          1.0e-10)

;;; ----------------------------------------------------------------------
;;;  END TUNABLES.  What follows is STATE, not settings: what one run
;;;  has to put back on the way out.
;;; ======================================================================

;;; -------------------- generic helpers ----------------------------------
;;;  The grouped build: the helpers come from CALOFIN-LIB.lsp.

;;; -------------------- points ------------------------------------------
;;;  A point record is (x y name): the name is what the report calls it,
;;;  so a finding reads "Pt. 17" whether 17 came off the block or off
;;;  the reading order.

(defun lobf:pt (p nm) (list (car p) (cadr p) nm))
(defun lobf:pt-name (q) (if (caddr q) (caddr q) "?"))

;; Every point in the selection: POINT entities and "ab_pt" blocks
;; wherever they sit, other blocks only on the points layer.  Returns
;; the deduped list; LOBF's own preview objects are never read back.
(defun lobf:harvest (ss / i en ed typ lay nm pts npt)
  (setq pts nil npt 0 i 0)
  (while (< i (sslength ss))
    (setq en (ssname ss i)
          ed (entget en)
          i  (1+ i))
    (if ed
      (progn
        (setq typ (cdr (assoc 0 ed))
              lay (strcase (cdr (assoc 8 ed))))
        (if (not (or (= lay (strcase lobf:*preview-layer*))
                     (= lay (strcase lobf:*ign-layer*))
                     (= lay (strcase lobf:*layer*))
                     (assoc -3 (entget en (list lobf:*appid*)))))
          (cond
            ;; ab_pt blocks are survey points wherever they sit
            ((and (= typ "INSERT")
                  (= (strcase (cdr (assoc 2 ed)))
                     (strcase lobf:*pt-block*)))
             (setq npt (1+ npt)
                   nm  (cal:block-number en lobf:*pt-tag*)
                   pts (cons (lobf:pt (cdr (assoc 10 ed))
                                      (if (and nm (/= nm "")) nm (itoa npt)))
                             pts)))
            ;; a plain POINT counts on any layer - the selection is
            ;; explicit, so there is no guessing involved
            ((= typ "POINT")
             (setq npt (1+ npt)
                   pts (cons (lobf:pt (cdr (assoc 10 ed)) (itoa npt)) pts)))
            ;; other blocks only count as points on the points layer
            ((= typ "INSERT")
             (if (= lay (strcase lobf:*pt-layer*))
               (setq npt (1+ npt)
                     nm  (cal:block-number en lobf:*pt-tag*)
                     pts (cons (lobf:pt (cdr (assoc 10 ed))
                                        (if (and nm (/= nm "")) nm (itoa npt)))
                               pts)))))))))
  (cal:dedupe (reverse pts) lobf:*exact-eps*))

;;; -------------------- the three fits ----------------------------------
;;;  A LINE is (origin direction): a point on it and a unit vector along
;;;  it.  Every fit below returns one, or nil when the points it was
;;;  given have no direction in them at all.

;; Perpendicular distance from P to the line, signed: positive on the
;; left of the direction, negative on the right.  Which side a point
;; falls on is what makes a band a band.
(defun lobf:sresid (p org dir)
  (cal:dot (cal:v- p org) (cal:perp dir)))

(defun lobf:resid (p org dir) (abs (lobf:sresid p org dir)))

;; FIT 1 -- least squares on the PERPENDICULAR distances (total least
;; squares), which is the line of best fit proper: it does not care
;; which axis you happened to call x, so a wall running north-south
;; fits as well as one running east-west.  The line goes through the
;; centroid along the principal axis of the scatter, and that axis is
;; the half-angle of (2*Sxy, Sxx-Syy).
(defun lobf:tls (pts / n cx cy sxx syy sxy p dx dy th)
  (setq n (length pts))
  (if (< n 2)
    nil
    (progn
      (setq cx 0.0 cy 0.0)
      (foreach p pts (setq cx (+ cx (car p)) cy (+ cy (cadr p))))
      (setq cx  (/ cx n)
            cy  (/ cy n)
            sxx 0.0
            syy 0.0
            sxy 0.0)
      (foreach p pts
        (setq dx  (- (car p) cx)
              dy  (- (cadr p) cy)
              sxx (+ sxx (* dx dx))
              syy (+ syy (* dy dy))
              sxy (+ sxy (* dx dy))))
      ;; every point on one spot: there is no direction to return, and
      ;; returning the X axis would be an answer the points never gave
      (if (< (+ sxx syy) lobf:*tiny*)
        nil
        (progn
          (setq th (* 0.5 (atan (* 2.0 sxy) (- sxx syy))))
          (list (list cx cy) (list (cos th) (sin th))))))))

;; PTS with the K'th (0-based) taken out.
(defun lobf:without (pts k / i out p)
  (setq i 0 out nil)
  (foreach p pts
    (if (/= i k) (setq out (cons p out)))
    (setq i (1+ i)))
  (reverse out))

;; The worst and the mean perpendicular distance of PTS from a line.
(defun lobf:spread (pts org dir / worst total d p n)
  (setq worst 0.0 total 0.0 n (length pts))
  (foreach p pts
    (setq d     (lobf:resid p org dir)
          total (+ total d))
    (if (> d worst) (setq worst d)))
  (list worst (if (> n 0) (/ total n) 0.0)))

;; FIT 2 -- the best fit that sets ONE point aside.  Every point is
;; tried as the one to leave out and the drop that leaves the REST
;; tightest wins, worst-held first and the mean as the tie-break: the
;; claim this fit makes is "the others sit on the line", so the
;; measure of a good drop is how tight the others end up, not how far
;; away the dropped one was.  Returns (origin dir index-dropped), or
;; nil when there are too few points for dropping one to mean
;; anything.
(defun lobf:drop1 (pts / n k sub f sp best bworst bmean)
  (setq n (length pts) k 0 best nil bworst nil bmean nil)
  (if (< n 3)
    nil
    (progn
      (while (< k n)
        (setq sub (lobf:without pts k)
              f   (lobf:tls sub))
        (if f
          (progn
            (setq sp (lobf:spread sub (car f) (cadr f)))
            (if (or (null best)
                    (< (car sp) (- bworst lobf:*tiny*))
                    (and (< (car sp) (+ bworst lobf:*tiny*))
                         (< (cadr sp) bmean)))
              (setq best   (list (car f) (cadr f) k)
                    bworst (car sp)
                    bmean  (cadr sp)))))
        (setq k (1+ k)))
      best)))

;; Convex hull, counterclockwise, by gift wrapping.  Points lying ON an
;; edge are dropped -- the tie goes to the farther one -- so a run that
;; really is a straight line comes back as just its two ends, which is
;; the case this tool sees most.  Gift wrapping is O(n*h) and h is
;; small for a near-straight cloud, so no sort is needed.
(defun lobf:hull (pts / start cur nxt out cr p guard)
  (setq start (car pts))
  (foreach p pts
    (if (or (< (car p) (car start))
            (and (= (car p) (car start)) (< (cadr p) (cadr start))))
      (setq start p)))
  (setq cur start out nil guard (1+ (length pts)))
  (while (> guard 0)
    (setq out   (cons cur out)
          guard (1- guard)
          nxt   nil)
    (foreach p pts
      (cond
        ((< (cal:dist p cur) lobf:*exact-eps*) nil)     ; itself
        ((null nxt) (setq nxt p))
        (T
         (setq cr (cal:cross (cal:v- nxt cur) (cal:v- p cur)))
         (if (or (> cr lobf:*tiny*)
                 (and (< (abs cr) lobf:*tiny*)
                      (> (cal:dist cur p) (cal:dist cur nxt))))
           (setq nxt p)))))
    (if (or (null nxt) (< (cal:dist nxt start) lobf:*exact-eps*))
      (setq guard 0)
      (setq cur nxt)))
  (reverse out))

;; FIT 3 -- the least-MAX (Chebyshev) fit: the narrowest band that
;; still holds every point, with the line down its middle.  The
;; narrowest such band is always flush with an edge of the convex hull,
;; so only the hull's own edges are tried and the best of them wins.
(defun lobf:minimax (pts / hull n i a b dir best bw lo hi s p)
  (setq hull (lobf:hull pts) n (length hull) i 0 best nil bw nil)
  (if (< n 2)
    nil
    (progn
      (while (< i n)
        (setq a   (nth i hull)
              b   (nth (rem (1+ i) n) hull)
              dir (cal:unit (cal:v- b a))
              i   (1+ i))
        (if dir
          (progn
            (setq lo nil hi nil)
            (foreach p pts
              (setq s (lobf:sresid p a dir))
              (if (or (null lo) (< s lo)) (setq lo s))
              (if (or (null hi) (> s hi)) (setq hi s)))
            (if (or (null bw) (< (- hi lo) (- bw lobf:*tiny*)))
              (setq bw   (- hi lo)
                    ;; the line sits halfway between the two rails, so
                    ;; the worst point on each side is equally off
                    best (list (cal:v+ a (cal:v* (cal:perp dir)
                                                   (* 0.5 (+ lo hi))))
                               dir))))))
      best)))

;;; -------------------- candidates --------------------------------------
;;;  A CANDIDATE is what the picker, the table and the drawing all read:
;;;
;;;    (aim origin dir ignored worst mean nheld off)
;;;
;;;  aim      the words the table prints for it
;;;  origin   a point on the line, dir a unit vector along it
;;;  ignored  the point record this fit set aside, or nil
;;;  worst    the furthest of the points it HELD is off it
;;;  mean     their average distance off it
;;;  nheld    how many points that is
;;;  off      how far the ignored point is off it, nil when none

(defun lobf:cand-aim (c)  (nth 0 c))
(defun lobf:cand-org (c)  (nth 1 c))
(defun lobf:cand-dir (c)  (nth 2 c))
(defun lobf:cand-ign (c)  (nth 3 c))
(defun lobf:cand-worst (c) (nth 4 c))
(defun lobf:cand-mean (c) (nth 5 c))
(defun lobf:cand-nheld (c) (nth 6 c))
(defun lobf:cand-off (c)  (nth 7 c))

;; Wrap a bare (origin dir) up as a candidate, measured over HELD and
;; with IGN (a point record, or nil) named as the one it let go.
(defun lobf:cand (aim line held ign / sp)
  (if (null line)
    nil
    (progn
      (setq sp (lobf:spread held (car line) (cadr line)))
      (list aim (car line) (cadr line) ign (car sp) (cadr sp)
            (length held)
            (if ign (lobf:resid ign (car line) (cadr line)) nil)))))

;; The three, in the order they are numbered on screen.  Any that
;; cannot be built is nil and is left out by the caller, so a
;; three-point run that degenerates still offers what it has.
(defun lobf:candidates (pts / one two three d ign held)
  (setq one   (lobf:cand "every point" (lobf:tls pts) pts nil)
        d     (lobf:drop1 pts)
        three (lobf:cand "tightest band" (lobf:minimax pts) pts nil))
  (if d
    (setq ign  (nth (caddr d) pts)
          held (lobf:without pts (caddr d))
          two  (lobf:cand (strcat "Pt. " (lobf:pt-name ign) " set aside")
                          (list (car d) (cadr d)) held ign)))
  (list one two three))

;; The colour candidate N is previewed in.  lobf:*fit-colors* is a
;; knob, so a list shorter than the number of fits is possible; white
;; is better there than the nil that would make an unusable DXF group.
(defun lobf:fit-color (n / c)
  (setq c (nth (1- n) lobf:*fit-colors*))
  (if c c 7))

;;; -------------------- which one Enter takes ---------------------------

;; Is the point fit 2 set aside a real outlier, or just the least good
;; of a set that is all about equally good?  Both halves of the rule
;; have to hold: drastically worse than the points the fit KEPT, and
;; far enough off in its own right to be worth blaming.  Returns the
;; ratio when it is, nil when it is not - the caller prints the number
;; either way, so the rule is never a verdict without its evidence.
(defun lobf:ratio (c / w)
  (if (and c (lobf:cand-off c))
    (progn
      (setq w (lobf:cand-worst c))
      ;; the held points are exactly on the line: the ratio is infinite
      ;; and there is no number to print, which lobf:outlier-p reads as
      ;; "drastic" and the report reads as "say it without one"
      (if (< w lobf:*tiny*) nil (/ (lobf:cand-off c) w)))))

;; T when fit 2 is the one to offer.
(defun lobf:outlier-p (c / r)
  (and c
       (lobf:cand-off c)
       (>= (lobf:cand-off c) lobf:*drastic-floor*)
       (progn
         (setq r (lobf:ratio c))
         (or (null r) (>= r lobf:*drastic*)))))

;;; -------------------- printing ----------------------------------------

;; The fit Enter takes when no point stands out.  Clamped, because
;; lobf:*default-fit* is a knob and the answer is used as an index.
(defun lobf:fallback-fit ()
  (if (member lobf:*default-fit* '("1" "2" "3")) lobf:*default-fit* "1"))

(defun lobf:dstr (d) (rtos d lobf:*dist-mode* lobf:*dist-prec*))

;; The bearing of a line, in degrees, folded into [0, 180): a line has
;; no arrowhead, so 183 degrees and 3 degrees are the same line and
;; must print as the same number.
(defun lobf:bearing (dir / a)
  (setq a (/ (* 180.0 (atan (cadr dir) (car dir))) pi))
  (while (< a 0.0) (setq a (+ a 180.0)))
  (while (>= a 180.0) (setq a (- a 180.0)))
  (strcat (rtos a 2 lobf:*ang-prec*) " deg"))

;; The word for an ACI colour, so the table names the colour actually
;; drawn instead of saying "green" whatever lobf:*fit-colors* holds.
(defun lobf:color-name (aci / q)
  (setq q (assoc aci '((1 . "red") (2 . "yellow") (3 . "green")
                       (4 . "cyan") (5 . "blue") (6 . "magenta")
                       (7 . "white") (8 . "grey"))))
  (if q (cdr q) (strcat "colour " (itoa aci))))

;; One row of the comparison table.
(defun lobf:row (n c col)
  (princ (strcat "\n   " (itoa n) "  "
                 (cal:pad (lobf:cand-aim c) 22)
                 (cal:pad (lobf:dstr (lobf:cand-worst c)) 14)
                 (cal:pad (lobf:dstr (lobf:cand-mean c)) 14)
                 (cal:pad (itoa (lobf:cand-nheld c)) 8)
                 (cal:pad (lobf:bearing (lobf:cand-dir c)) 11)
                 (lobf:color-name col))))

;;; -------------------- drawing -----------------------------------------

;; Everything LOBF creates carries a small piece of extended data naming
;; this command, so a later run never reads its own preview back as a
;; point and only stamped objects are ever erased again.
(defun lobf:tag-mine (en / ed)
  (if en
    (progn
      (regapp lobf:*appid*)
      (setq ed (entget en))
      (entmod (append ed (list (list -3 (list lobf:*appid*
                                              (cons 1000 lobf:*appid*))))))))
  en)

;; An infinite construction line: DXF 10 is a point on it, DXF 11 the
;; unit direction.
(defun lobf:xline (org dir lay col)
  (lobf:tag-mine
    (entmakex (list '(0 . "XLINE") '(100 . "AcDbEntity")
                    (cons 8 lay) (cons 62 col) '(100 . "AcDbXline")
                    (cons 10 (list (car org) (cadr org) 0.0))
                    (cons 11 (list (car dir) (cadr dir) 0.0))))))

(defun lobf:line (a b lay col)
  (lobf:tag-mine
    (entmakex (list '(0 . "LINE") '(100 . "AcDbEntity")
                    (cons 8 lay) (cons 62 col) '(100 . "AcDbLine")
                    (cons 10 (list (car a) (cadr a) 0.0))
                    (cons 11 (list (car b) (cadr b) 0.0))))))

(defun lobf:label (pt hgt str lay col)
  (lobf:tag-mine
    (entmakex (list '(0 . "TEXT") '(100 . "AcDbEntity")
                    (cons 8 lay) (cons 62 col) '(100 . "AcDbText")
                    (cons 10 (list (car pt) (cadr pt) 0.0))
                    (cons 40 hgt) (cons 1 str)))))

(defun lobf:ring (pt r lay col)
  (lobf:tag-mine
    (entmakex (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                    (cons 8 lay) (cons 62 col) '(100 . "AcDbCircle")
                    (cons 10 (list (car pt) (cadr pt) 0.0))
                    (cons 40 r)))))

;; How far along DIR the points reach, as (lowest highest), measured
;; from ORG.  The labels stand past the high end of that run.
(defun lobf:extent (pts org dir / lo hi s p)
  (foreach p pts
    (setq s (cal:dot (cal:v- p org) dir))
    (if (or (null lo) (< s lo)) (setq lo s))
    (if (or (null hi) (> s hi)) (setq hi s)))
  (list (if lo lo 0.0) (if hi hi 0.0)))

;; How long the run of points is, measured along the line: the size
;; everything the labels do is scaled from.
(defun lobf:runlen (pts org dir / ex)
  (setq ex (lobf:extent pts org dir))
  (- (cadr ex) (car ex)))

;; Draw one candidate: the XLINE, its number on a stalk out to the side
;; so the label cannot be read against the wrong line, and a ring round
;; the point it set aside.  Returns (xline . furniture), the furniture
;; being everything that goes when a single fit is kept.
(defun lobf:draw (n c pts hgt col / org dir ex base tip xl fur)
  (setq org (lobf:cand-org c)
        dir (lobf:cand-dir c)
        ex  (lobf:extent pts org dir)
        xl  (lobf:xline org dir lobf:*preview-layer* col)
        fur nil
        ;; out past the last point, then off the line by n stalks, so
        ;; the three numbers stack instead of overprinting
        base (cal:v+ org
                      (cal:v* dir (+ (cadr ex)
                                      (* lobf:*label-gap*
                                         (max (- (cadr ex) (car ex))
                                              1.0)))))
        tip  (cal:v+ base (cal:v* (cal:perp dir)
                                    (* n lobf:*label-stalk* hgt))))
  (setq fur (cons (lobf:line base tip lobf:*preview-layer* col) fur))
  (setq fur (cons (lobf:label (cal:v+ tip (cal:v* (cal:perp dir)
                                                    (* 0.3 hgt)))
                              hgt (itoa n) lobf:*preview-layer* col)
                  fur))
  (if (lobf:cand-ign c)
    (progn
      (cal:ensure-layer lobf:*ign-layer* lobf:*ign-color*)
      (setq fur (cons (lobf:ring (lobf:cand-ign c)
                                 (* lobf:*ring-scale* hgt)
                                 lobf:*ign-layer* col)
                      fur))))
  (cons xl (reverse fur)))

(defun lobf:erase (en)
  (if (and en (entget en)) (entdel en))
  nil)

;; A kept object takes its layer's colour.  The preview colours mean
;; "this one belongs to candidate 2"; once there is one candidate left
;; they mean nothing, and a ring left standing in fit 2's yellow on a
;; red layer says the layer colour is not to be trusted.
(defun lobf:bylayer (en / ed)
  (if (and en (setq ed (entget en)) (assoc 62 ed))
    (entmod (subst '(62 . 256) (assoc 62 ed) ed)))
  en)

;; Move a kept line off the preview layer onto the output one.
(defun lobf:relayer (en lay / ed)
  (if (and en (setq ed (entget en)))
    (entmod (subst (cons 8 lay) (assoc 8 ed) ed)))
  en)

;;; -------------------- asking ------------------------------------------

;; The fit picker, the section-3 multi-fit set: click the line you want
;; or type its number, All keeps the three as previewed, None keeps
;; nothing, and Redo is this prompt's way back -- it drops the trio and
;; asks for the points again.  DFLT is what Enter takes and is worked
;; out per run, not fixed: fit 2 when it found a real outlier, the
;; balanced fit when it did not.
(defun lobf:askfit (dflt draws / pick sel picked i d)
  (princ "\n\n  Click the line you want to keep, or type its number.")
  (princ "\n  Redo asks for the points again; None leaves the drawing as it was.")
  (initget "1 2 3 All None Redo")
  (setq pick (getkword (strcat "\n  Keep which fit - click one, or"
                               " [1/2/3/All/None/Redo] <" dflt ">: ")))
  (if lzd:ask (lzd:ask "lobf:askfit" pick))
  (if (null pick)
    ;; no keyword typed: give them a click, and fall back to the
    ;; default this run worked out
    (progn
      (setq sel (entsel (strcat "\n  Pick the line to keep (or Enter for "
                                dflt "): ")))
      (if lzd:watch (lzd:watch sel))
      (if sel
        (progn
          (setq picked (car sel) i 1)
          (foreach d draws
            (if (and d (or (eq picked (car d)) (member picked (cdr d))))
              (setq pick (itoa i)))
            (setq i (1+ i)))
          (if (null pick)
            (progn
              (princ (strcat "\n  (that is not one of them - keeping "
                             dflt ")"))
              (setq pick dflt))))
        (setq pick dflt))))
  pick)

;;; -------------------- the run -----------------------------------------

;; The comparison table, the outlier verdict under it, and the warning
;; when the points are not really a line at all.  Returns the number
;; Enter should take.
(defun lobf:report (cands pts / c k n one two dflt r run)
  (setq n 0)
  (foreach k cands (if k (setq n (1+ n))))
  (princ (strcat "\n\n  " (itoa (length pts))
                 " point(s) fitted.  " (itoa n)
                 " candidate line(s) are drawn on layer "
                 lobf:*preview-layer* ":"))
  (princ (strcat "\n\n   #  fit                   worst off     avg off"
                 "       held    bearing    colour"))
  (princ (strcat "\n   -  --------------------  ------------  ------------"
                 "  ------  ---------  ------"))
  (setq c 1)
  (foreach k cands
    (if k (lobf:row c k (lobf:fit-color c)))
    (setq c (1+ c)))
  (princ (strcat "\n\n  \"worst off\" and \"avg off\" are perpendicular"
                 " distances, measured only over"
                 "\n  the points each fit HELD - fit 2 holds one fewer,"
                 " which is the whole point of it."))
  (setq one (car cands) two (cadr cands))
  ;; the outlier rule, stated with the numbers that decided it
  (if two
    (progn
      (setq r    (lobf:ratio two)
            dflt (if (lobf:outlier-p two) "2" (lobf:fallback-fit)))
      (princ (strcat "\n\n  Fit 2 sets Pt. " (lobf:pt-name (lobf:cand-ign two))
                     " aside: it is " (lobf:dstr (lobf:cand-off two))
                     " off that line, against "
                     (lobf:dstr (lobf:cand-worst two))
                     " for the worst of the "
                     (itoa (lobf:cand-nheld two)) " it held"
                     (if r (strcat " - " (rtos r 2 1) " times") "")
                     "."))
      (if (= dflt "2")
        (princ (strcat "\n  That is the outlier this tool looks for, so"
                       " fit 2 is what Enter takes."))
        (princ (strcat "\n  That is not drastic enough to blame one point"
                       " (it takes " (rtos lobf:*drastic* 2 1) " times and "
                       (lobf:dstr lobf:*drastic-floor*)
                       "), so Enter takes fit " dflt " and every point"
                       " keeps its vote."))))
    (setq dflt (lobf:fallback-fit)))
  ;; the points may simply not be a line, and a line drawn through a
  ;; blob is a wrong answer that looks like a right one
  (if one
    (progn
      (setq run (lobf:runlen pts (lobf:cand-org one) (lobf:cand-dir one)))
      (if (and (> run lobf:*tiny*)
               (> (/ (lobf:cand-worst one) run) lobf:*blob-ratio*))
        (princ (strcat "\n\n  CAUTION: the worst point is "
                       (rtos (* 100.0 (/ (lobf:cand-worst one) run)) 2 0)
                       "% of the run's own length off the line."
                       "\n  These points may not be one straight line at"
                       " all - check the selection before you keep"
                       " anything.")))))
  dflt)

;; Everything after the points are in hand: draw, compare, choose.
;; Returns 'REDO when the picker asked for a fresh selection.
(defun lobf:run (pts / cands hgt run draws n c e dflt pick keep i res)
  (setq cands (lobf:candidates pts))
  (if (null (car cands))
    (progn
      (princ (strcat "\n" (itoa (length pts))
                     " point(s), but they are all too close together to"
                     " give a direction - there is no line in them."))
      nil)
    (progn
      (cal:ensure-layer lobf:*preview-layer* lobf:*preview-color*)
      ;; sized to the run the points cover, so the labels read at any
      ;; scale the sheet is drawn at
      (setq run (lobf:runlen pts (lobf:cand-org (car cands))
                             (lobf:cand-dir (car cands)))
            hgt (/ (max run 1.0) lobf:*label-div*)
            n   1
            draws nil)
      (foreach c cands
        (setq draws (cons (if c (lobf:draw n c pts hgt (lobf:fit-color n))
                              nil)
                          draws)
              n     (1+ n)))
      (setq draws (reverse draws)
            dflt  (lobf:report cands pts))
      ;; a fit that could not be built is not on offer, and Enter must
      ;; not take one either
      (if (null (nth (1- (atoi dflt)) cands)) (setq dflt "1"))
      (setq pick (lobf:askfit dflt draws))
      (cond
        ((= pick "Redo")
         (foreach c draws
           (if c
             (progn (lobf:erase (car c))
                    (foreach e (cdr c) (lobf:erase e)))))
         (princ "\n  The three are off the screen - highlight the points again.")
         (setq res 'REDO))
        ((= pick "None")
         (foreach c draws
           (if c
             (progn (lobf:erase (car c))
                    (foreach e (cdr c) (lobf:erase e)))))
         (princ "\n  All three erased - nothing was added to the drawing.")
         (setq res nil))
        ((= pick "All")
         (princ (strcat "\n  Keeping all of them on layer "
                        lobf:*preview-layer* ", in their preview colours"
                        " - with any set-aside point still ringed on "
                        lobf:*ign-layer* "."))
         (princ "\n  (the numbers and their stalks are kept too - erase them when done)")
         (setq res nil))
        (T
         (setq i 1)
         (foreach c draws
           (if c
             (if (= i (atoi pick))
               (setq keep c)
               (progn (lobf:erase (car c))
                      (foreach e (cdr c) (lobf:erase e)))))
           (setq i (1+ i)))
         (if (null keep)
           (princ (strcat "\n  Fit " pick " could not be built from these"
                          " points - nothing kept."))
           (progn
             ;; the stalk and the number were there to tell three lines
             ;; apart; one line does not need them.  The ring does not
             ;; go: it names the point this line gave up on, which is
             ;; the finding, not the furniture -- but it stops carrying
             ;; a candidate's colour, because there is no candidate to
             ;; tell it apart from any more.
             (foreach e (cdr keep)
               (if (and e (entget e))
                 (if (= "CIRCLE" (cdr (assoc 0 (entget e))))
                   (lobf:bylayer e)
                   (lobf:erase e))))
             (cal:ensure-layer lobf:*layer* lobf:*color*)
             (lobf:bylayer (lobf:relayer (car keep) lobf:*layer*))
             (setq c (nth (1- (atoi pick)) cands))
             (princ (strcat "\n  Keeping fit " pick " - " (lobf:cand-aim c)
                            " - on layer " lobf:*layer* ", bearing "
                            (lobf:bearing (lobf:cand-dir c)) "."))
             (if (lobf:cand-ign c)
               (princ (strcat "\n  Pt. " (lobf:pt-name (lobf:cand-ign c))
                              " is NOT on this line - it is "
                              (lobf:dstr (lobf:cand-off c))
                              " off it, and is ringed on layer "
                              lobf:*ign-layer* ".")))))
         (setq res nil)))
      res)))

;;; -------------------- the commands ------------------------------------

(defun c:LOBF ( / *error* undo-open ss pts again line)
  (defun *error* (msg)
    ;; user settings come back FIRST so nothing below can skip them
    (cal:sysrestore)
    ;; command-s, never plain command: 2015+ engines reject (command)
    ;; inside *error* unless the error mode was pushed beforehand
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nLOBF error: " msg)))
    (if lzd:report (lzd:report "LOBF" *lobf-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "LOBF" *lobf-version*))
  (cal:syssave '("CMDECHO"))
  (setvar "CMDECHO" 0)
  ;; a pickfirst selection if there is one - probed BEFORE the undo
  ;; group opens, because that command clears the set (the convention
  ;; ABPCHECK and abhd already carry)
  (setq ss (ssget "_I" lobf:*filter*))
  (if lzd:watch (lzd:watch ss))
  ;; only when undo is recording - _Begin in a drawing with UNDO
  ;; off (bit 1 of UNDOCTL clear) errors out of the command
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn
      (command "_.UNDO" "_Begin")
      (setq undo-open T)))
  (princ "\n\nLOBF - the construction line that best fits a row of points.")
  (setq again T)
  (while again
    (setq again nil)
    (if (null ss)
      (progn
        (princ "\nHighlight the points to fit (Enter = every point in the drawing): ")
        (setq ss (ssget lobf:*filter*))
        (if lzd:watch (lzd:watch ss))))
    (if (null ss) (setq ss (ssget "_X" lobf:*filter*)))
    (if (null ss)
      (princ "\nNothing to fit - no points in the drawing.")
      (progn
        (setq pts (lobf:harvest ss))
        (cond
          ((< (length pts) 2)
           (princ (strcat "\n" (itoa (length pts)) " point(s) found - it"
                          " takes two to make a line.  Looked for POINT"
                          " entities, \"" lobf:*pt-block*
                          "\" blocks anywhere, and blocks on layer "
                          lobf:*pt-layer* ".")))
          ;; two points are one line and no choice at all; drawing the
          ;; picker over three identical candidates would be theatre
          ((= (length pts) 2)
           (setq line (lobf:tls pts))
           (if (null line)
             (princ (strcat "\nThe two points are too close together to"
                            " give a direction - there is no line in"
                            " them."))
             (progn
               (cal:ensure-layer lobf:*layer* lobf:*color*)
               (lobf:xline (car line) (cadr line) lobf:*layer* 256)
               (princ (strcat "\nTwo points make exactly one line, so there"
                              " is nothing to choose between."
                              "\nDrawn on layer " lobf:*layer* ", bearing "
                              (lobf:bearing (cadr line)) ".")))))
          (T
           (if (eq 'REDO (lobf:run pts))
             (setq ss nil again T))))))
    ;; Redo is the only way round this loop again, and it is a keyword
    ;; the user has to type every time - so the run ends when they stop
    ;; asking for another one, and nothing here can spin on its own
    )
  (if undo-open (command "_.UNDO" "_End"))
  (setq undo-open nil)
  (cal:sysrestore)
  (princ))

(defun c:LOBFVER ()
  (princ (strcat "\nLOBF " *lobf-version* " loaded."))
  (princ))

(princ (strcat "\nLOBF " *lobf-version*
               " loaded.  Type LOBF to run."))
(princ)
